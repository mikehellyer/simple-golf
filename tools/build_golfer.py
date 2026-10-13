"""Build the lifelike golfer model for Simple-Golf.

Run inside headless Blender with the MPFB extension and the MakeHuman CC0
asset packs installed:

    blender -b -P tools/build_golfer.py -- [--render out.png] [--out golfer.glb]

The character is a MakeHuman (MPFB) human on the CMU MotionBuilder rig, so
the CMU motion-capture swings (subject 64) play on it bone for bone.
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCAP = os.path.expanduser("~/.local/opt/mocap")
BALL = (0.0, 0.0, 0.0)

CHARACTER = {
    "name": "Golfer",
    "phenotype": {
        "gender": 1.0, "age": 0.55, "muscle": 0.55, "weight": 0.5,
        "proportions": 0.6, "height": 0.55, "cupsize": 0.5, "firmness": 0.5,
        "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0},
    },
    "rig": "cmu_mb",
    "eyes": "high-poly/high-poly.mhclo",
    "eyebrows": "eyebrow001/eyebrow001.mhclo",
    "eyelashes": "eyelashes01/eyelashes01.mhclo",
    "hair": "short02/short02.mhclo",
    "proxy": "",
    "clothes": [
        "namuhekam_male_polo_shirt/namuhekam_male_polo_shirt.mhclo",
        "toigo_wool_pants/toigo_wool_pants.mhclo",
        "shoes01/shoes01.mhclo",
        "jujube_newsboy_cap/jujube_newsboy_cap.mhclo",
    ],
    "skin_mhmat": "middleage_caucasian_male/middleage_caucasian_male.mhmat",
    "skin_material_type": "MAKESKIN",
    "eyes_material_type": "MAKESKIN",
    "clothes_material_type": "MAKESKIN",
    "skin_material_settings": {},
    "eyes_material_settings": {},
    "targets": [],
    "expressions": [],
    "teeth": "",
    "tongue": "",
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--render", default="")
    p.add_argument("--out", default="")
    p.add_argument("--frame", default="")
    return p.parse_args(argv)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_character():
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    basemesh = HumanService.deserialize_from_dict(dict(CHARACTER), settings)
    rig = ObjectService.find_object_of_type_amongst_nearest_relatives(basemesh, "Skeleton")
    return basemesh, rig


def render(path, rig, frame):
    scene = bpy.context.scene
    if "cam" in bpy.data.objects:
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        return
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    view = os.environ.get("VIEW", "front")
    if view == "front":
        cam.location = (0.0, -4.2, 1.0)
        cam.rotation_euler = (math.radians(88), 0.0, 0.0)
    elif view == "hands":
        cam.location = (0.0, -2.0, 1.0)
        cam.rotation_euler = (math.radians(90), 0.0, 0.0)
        cam_data.lens = 120
    else:
        cam.location = (-4.2, -0.3, 1.0)
        cam.rotation_euler = (math.radians(88), 0.0, math.radians(-90))
    cam_data.lens = 40
    scene.camera = cam
    bpy.ops.mesh.primitive_plane_add(size=6.0)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.021, location=BALL)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.color = (0.5, 0.6, 0.7)
    scene.world = world
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --- Motion capture -----------------------------------------------------------

## CMU's BVH files are in units of 1/0.45 inch.
CMU_SCALE = 0.0254 / 0.45
## Target bones whose CMU counterparts are named differently.
BONE_MAP = {"LeftHandFinger1": "LeftHandIndex1", "RightHandFinger1": "RightHandIndex1"}


def sample_bvh(name, step):
    """Imports a CMU BVH and samples every bone's world matrix.

    The capture is turned so the golfer faces -Y with the target along +X,
    which glTF export makes Godot's golfer frame (+X target, +Z to the ball).
    Frame 1 of these files is a calibration T-pose and is skipped.
    """
    path = os.path.join(MOCAP, name + ".bvh")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.import_anim.bvh(filepath=path, global_scale=CMU_SCALE, rotate_mode="NATIVE",
                            axis_forward="-Z", axis_up="Y", update_scene_fps=False,
                            update_scene_duration=False)
    src = bpy.context.object
    scene = bpy.context.scene
    scene.frame_set(1)
    # The rest pose faces -Y like MakeHuman's, so take it before turning.
    rest = {b.name: (src.matrix_world @ b.matrix_local).copy() for b in src.data.bones}
    short = {b.name for b in src.data.bones if b.length < 0.01}
    tpose_hips = (src.matrix_world @ src.pose.bones["Hips"].head).z
    src.rotation_euler = (0.0, 0.0, -math.pi / 2.0)
    last = int(src.animation_data.action.frame_range[1])
    frames = []
    for f in range(2, last + 1, step):
        scene.frame_set(f)
        frames.append({pb.name: (src.matrix_world @ pb.matrix).copy() for pb in src.pose.bones})
    bpy.data.objects.remove(src)
    return {"rest": rest, "short": short, "hips": tpose_hips, "frames": frames}


def retarget(rig, mocap, name):
    """Builds an action on rig that copies the capture bone for bone.

    Each bone takes the source bone's world rotation away from its T-pose.
    The target's A-pose rest is first swung onto the source's T-pose
    direction, so arms that hang at rest still follow the capture exactly.
    """
    bones = [b for b in rig.data.bones if b.name != "Club"]
    world = rig.matrix_world.to_3x3().normalized()
    rest_arm = {b.name: b.matrix_local.copy() for b in bones}
    convert = {}
    for b in bones:
        src = BONE_MAP.get(b.name, b.name)
        rt = (rig.matrix_world @ b.matrix_local).to_3x3().normalized()
        if src not in mocap["rest"]:
            continue
        rs = mocap["rest"][src].to_3x3().normalized()
        if src in mocap["short"] or b.name == "Hips":
            # Too short to have a direction: inherit the parent's correction.
            parent = b.parent
            align = convert[parent.name][1] if parent and parent.name in convert else Matrix.Identity(3)
        else:
            align = rt.col[1].rotation_difference(rs.col[1]).to_matrix()
        convert[b.name] = (rs.inverted() @ align @ rt, align, src)

    hips_ratio = rest_arm["Hips"].translation.z / mocap["hips"]
    action = bpy.data.actions.new(name)
    keys = {b.name: [] for b in bones}
    hips_keys = []
    prev = {}
    for i, frame in enumerate(mocap["frames"]):
        rot_arm = {}
        for b in bones:
            rt_arm = rest_arm[b.name].to_3x3().normalized()
            if b.name in convert:
                c, _, src = convert[b.name]
                r_world = frame[src].to_3x3().normalized() @ c
                rot_arm[b.name] = world.inverted() @ r_world
            elif b.parent:
                rp = rest_arm[b.parent.name].to_3x3().normalized()
                rot_arm[b.name] = rot_arm[b.parent.name] @ rp.inverted() @ rt_arm
            else:
                rot_arm[b.name] = rt_arm
            if b.parent:
                local = (rest_arm[b.parent.name].inverted() @ rest_arm[b.name]).to_3x3().normalized()
                basis = local.inverted() @ rot_arm[b.parent.name].inverted() @ rot_arm[b.name]
            else:
                basis = rt_arm.inverted() @ rot_arm[b.name]
            q = basis.to_quaternion()
            if b.name in prev:
                q.make_compatible(prev[b.name])
            prev[b.name] = q
            keys[b.name].append(q)
        hips = frame["Hips"].translation * hips_ratio
        hips_rest = rest_arm["Hips"]
        hips_keys.append(hips_rest.to_3x3().normalized().inverted() @ (rig.matrix_world.inverted() @ hips - hips_rest.translation))

    n = len(mocap["frames"])
    for b in bones:
        rig.pose.bones[b.name].rotation_mode = "QUATERNION"
        path = 'pose.bones["%s"].rotation_quaternion' % b.name
        for axis in range(4):
            fc = action.fcurves.new(path, index=axis, action_group=b.name)
            fc.keyframe_points.add(n)
            co = []
            for f, q in enumerate(keys[b.name]):
                co += [f + 1, q[axis]]
            fc.keyframe_points.foreach_set("co", co)
            fc.update()
    path = 'pose.bones["Hips"].location'
    for axis in range(3):
        fc = action.fcurves.new(path, index=axis, action_group="Hips")
        fc.keyframe_points.add(n)
        co = []
        for f, v in enumerate(hips_keys):
            co += [f + 1, v[axis]]
        fc.keyframe_points.foreach_set("co", co)
        fc.update()
    action.use_fake_user = True
    # Assign once the curves exist, so Blender binds the action's slot to them.
    if not rig.animation_data:
        rig.animation_data_create()
    rig.animation_data.action = None
    rig.animation_data.action = action
    return action


def hands_track(rig, action):
    """Midpoint of the wrists, in world space, for every frame of action."""
    rig.animation_data.action = action
    scene = bpy.context.scene
    track = []
    for f in range(1, int(action.frame_range[1]) + 1):
        scene.frame_set(f)
        pb = rig.pose.bones
        track.append((rig.matrix_world @ ((pb["LeftHand"].head + pb["RightHand"].head) / 2)).copy())
    return track


# --- The club ------------------------------------------------------------------

BALL_RADIUS = 0.021
## Each stroke: its capture, the club's lie (the shaft's angle up from the
## ground at address), how far the wrists hinge at the top, and how long the
## downswing keeps that hinge (the "lag") before releasing it into the ball.
## Full shots are built for a mid-iron; Godot lengthens and tilts the club for
## the others (see golfer.gd).
STROKES = {
    "swing": {"bvh": "64_01", "lie": 62.0, "hinge": 95.0, "hinge_by": 100.0, "lag_until": 60.0},
    "putt": {"bvh": "64_12", "lie": 72.0, "hinge": 0.0, "hinge_by": 100.0, "lag_until": 60.0},
}


def add_club_bone(rig):
    """A free bone the club hangs from: Y runs down the shaft to the head."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bone = rig.data.edit_bones.new("Club")
    bone.head = (0.0, 0.0, 0.0)
    bone.tail = (0.0, 0.1, 0.0)
    bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.pose.bones["Club"].rotation_mode = "QUATERNION"


def _grip(pb):
    return (pb["LeftHand"].head + pb["RightHand"].head) / 2.0


def _signed_angle(a, b, n):
    return math.atan2(n.dot(a.cross(b)), a.dot(b))


def club_track(rig, action, stroke):
    """Swings the club on one plane: arms and a hinging wrist, as a two-lever
    model, then bakes it onto the Club bone. Returns the stroke's markers."""
    lie = math.radians(stroke["lie"])
    hinge_max = math.radians(stroke["hinge"])
    hinge_by = math.radians(stroke["hinge_by"])
    lag_until = math.radians(stroke["lag_until"])
    rig.animation_data.action = None
    rig.animation_data.action = action
    scene = bpy.context.scene
    pb = rig.pose.bones
    n_frames = int(action.frame_range[1])
    target = Vector((1.0, 0.0, 0.0))
    samples = []
    for f in range(1, n_frames + 1):
        scene.frame_set(f)
        centre = (pb["LeftArm"].head + pb["RightArm"].head) / 2.0
        samples.append((_grip(pb).copy(), centre.copy()))

    grip0, centre0 = samples[0]
    # At address the shaft runs from the hands down to the ball, which sits
    # straight out in front of them; the swing plane holds the shaft and the
    # target line.
    drop = grip0.z - BALL_RADIUS
    reach = drop / math.tan(lie)
    club_length = drop / math.sin(lie)
    shaft0 = Vector((0.0, -reach, -drop)).normalized()
    normal = target.cross(shaft0).normalized()

    def in_plane(v):
        return (v - normal * v.dot(normal)).normalized()

    arm0 = in_plane(grip0 - centre0)
    # Unwrapped, since the arms go most of the way round.
    phi = [0.0]
    prev = arm0
    for g, c in samples[1:]:
        cur = in_plane(g - c)
        phi.append(phi[-1] + _signed_angle(prev, cur, normal))
        prev = cur
    # Backswing angles are positive: the first big move takes the hands back.
    amplitude = max(abs(p) for p in phi)
    first = next(p for p in phi if abs(p) > amplitude * 0.3)
    sign = 1.0 if first > 0.0 else -1.0
    phi = [p * sign for p in phi]
    back = max(phi)
    swing_end = next(i for i in range(n_frames) if phi[i] < -back * 0.3)
    top = max(range(swing_end), key=lambda i: phi[i])
    impact = next((i for i in range(top, n_frames) if phi[i] <= 0.0), n_frames - 1)
    finish = min(range(impact, n_frames), key=lambda i: phi[i])
    start = next((i for i in range(top) if phi[i] > back * 0.03), 0)

    def hinge(i):
        p = phi[i]
        if i <= top:
            return hinge_max * _smooth(0.0, hinge_by, p)
        if i <= impact:
            return hinge_max * _smooth(0.0, lag_until, p)
        return -hinge_max * _smooth(0.0, hinge_by, -p)

    dirs = []
    for i in range(n_frames):
        angle = (phi[i] + hinge(i)) * sign
        dirs.append(Quaternion(normal, angle) @ shaft0)
    # The hands come into the ball a little higher than they started, so
    # tilt the shaft down around impact until the club meets the ball.
    g, d = samples[impact][0], dirs[impact]
    best, err = 0.0, 1e9
    for k in range(-400, 401):
        t = math.radians(k * 0.05)
        h = g + (Quaternion(normal, t) @ d) * club_length
        e = abs(h.z - BALL_RADIUS) + abs(h.y - (grip0.y - reach)) * 0.3
        if e < err:
            best, err = t, e
    width = 0.12 * scene.render.fps
    for i in range(n_frames):
        w = math.exp(-((i - impact) / width) ** 2)
        dirs[i] = Quaternion(normal, best * w) @ dirs[i]

    world_inv = rig.matrix_world.inverted()
    keys = []
    for i in range(n_frames):
        y = dirs[i].normalized()
        z = normal
        x = y.cross(z).normalized()
        z = x.cross(y).normalized()
        m = Matrix((x, y, z)).transposed().to_4x4()
        m.translation = samples[i][0]
        keys.append(world_inv @ m)

    path_rot = 'pose.bones["Club"].rotation_quaternion'
    path_loc = 'pose.bones["Club"].location'
    prev = None
    quats = []
    for m in keys:
        q = m.to_quaternion()
        if prev is not None:
            q.make_compatible(prev)
        prev = q
        quats.append(q)
    for axis in range(4):
        fc = action.fcurves.new(path_rot, index=axis, action_group="Club")
        fc.keyframe_points.add(n_frames)
        fc.keyframe_points.foreach_set("co", [v for i, q in enumerate(quats) for v in (i + 1, q[axis])])
        fc.update()
    for axis in range(3):
        fc = action.fcurves.new(path_loc, index=axis, action_group="Club")
        fc.keyframe_points.add(n_frames)
        fc.keyframe_points.foreach_set("co", [v for i, m in enumerate(keys) for v in (i + 1, m.translation[axis])])
        fc.update()
    rig.animation_data.action = None
    rig.animation_data.action = action
    grip_hands(rig, action, [k.to_3x3() for k in keys])
    fps = scene.render.fps
    marks = {"start": start / fps, "top": top / fps, "impact": impact / fps, "finish": finish / fps,
             "end": (n_frames - 1) / fps, "club_length": club_length, "lie": stroke["lie"],
             "ball": _godot(grip0 + shaft0 * club_length), "grip": _godot(grip0)}
    print("MARKS", action.name, marks, "ball", tuple(round(v, 3) for v in (grip0 + shaft0 * club_length)),
          "impact tilt %.1f" % math.degrees(best))
    return marks


## How far the fingers and thumbs close round the grip.
FINGER_CURL = math.radians(75.0)
THUMB_CURL = math.radians(30.0)


def grip_hands(rig, action, club_rots):
    """Puts the hands on the club. The capture's wrist angles are noisy, so
    each hand instead turns with the club, from a grip set at address: the
    hand runs down the shaft, the left palm facing away from the target and
    the right palm towards it. The fingers close round the grip."""
    scene = bpy.context.scene
    pb = rig.pose.bones
    fcurves = {(fc.data_path, fc.array_index): fc for fc in action.fcurves}
    world = rig.matrix_world.to_3x3().normalized()
    for side, palm in (("Left", Vector((-1.0, 0.0, 0.0))), ("Right", Vector((1.0, 0.0, 0.0)))):
        hand = rig.data.bones[side + "Hand"]
        rest = hand.matrix_local.to_3x3().normalized()
        # Which hand axis is the palm: the one that points across the body in
        # the rest pose, where the arms hang with palms to the thighs.
        inward = Vector((-1.0, 0.0, 0.0)) if side == "Left" else Vector((1.0, 0.0, 0.0))
        axis = max(((i, sgn) for i in (0, 2) for sgn in (1.0, -1.0)),
                   key=lambda a: (rest.col[a[0]] * a[1]).dot(inward))
        shaft = club_rots[0].col[1]
        palm_w = (palm - shaft * palm.dot(shaft)).normalized()
        y = shaft
        cols = [None, y, None]
        cols[axis[0]] = palm_w * axis[1]
        other = 2 - axis[0]
        cols[other] = cols[(other + 1) % 3].cross(cols[(other + 2) % 3]).normalized()
        want0 = Matrix((cols[0], cols[1], cols[2])).transposed()
        offset = club_rots[0].inverted() @ want0
        parent = rig.data.bones[side + "ForeArm"]
        local = (parent.matrix_local.inverted() @ hand.matrix_local).to_3x3().normalized()
        path = 'pose.bones["%s"].rotation_quaternion' % (side + "Hand")
        prev = None
        for i, club in enumerate(club_rots):
            scene.frame_set(i + 1)
            rp = pb[side + "ForeArm"].matrix.to_3x3().normalized()
            want = world.inverted() @ (world @ club) @ offset
            q = (local.inverted() @ rp.inverted() @ want).to_quaternion()
            if prev is not None:
                q.make_compatible(prev)
            prev = q
            for k in range(4):
                fcurves[(path, k)].keyframe_points[i].co[1] = q[k]
        for name, angle in ((side + "HandFinger1", FINGER_CURL), (side[0] + "Thumb", THUMB_CURL)):
            q = Quaternion(Vector((1.0, 0.0, 0.0)), angle)
            fpath = 'pose.bones["%s"].rotation_quaternion' % name
            for k in range(4):
                fc = fcurves.get((fpath, k))
                if fc:
                    for kp in fc.keyframe_points:
                        kp.co[1] = q[k]
    for fc in action.fcurves:
        fc.update()


def _godot(v):
    """A Blender point in Godot's axes (glTF: Y up, Z towards the viewer)."""
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def add_club_mesh(rig, length):
    """A stand-in club for checking renders in Blender (Godot draws its own)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=length, location=(0, length / 2, 0),
                                        rotation=(math.pi / 2, 0, 0))
    shaft = bpy.context.object
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.04, length, 0))
    head = bpy.context.object
    head.scale = (0.08, 0.02, 0.05)
    for o in (shaft, head):
        o.parent = rig
        o.parent_type = "BONE"
        o.parent_bone = "Club"
        # Bone parenting hangs children from the bone's tail; pull back to the head.
        o.location.y -= 0.1
    return shaft, head


# --- Export ---------------------------------------------------------------------

def bake_body(basemesh):
    """Folds the body-shape morphs into the mesh: the game only animates bones."""
    bpy.context.view_layer.objects.active = basemesh
    if basemesh.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)


## Texture sizes: the golfer is never more than a third of the screen high.
MAX_TEXTURE = 1024
EYE_TEXTURE = 256


def shrink_textures():
    for image in bpy.data.images:
        if image.size[0] == 0:
            continue
        limit = EYE_TEXTURE if "eye" in image.name.lower() and "brow" not in image.name.lower() else MAX_TEXTURE
        if image.size[0] > limit or image.size[1] > limit:
            image.scale(min(image.size[0], limit), min(image.size[1], limit))


def export(rig, actions, path):
    """Writes the character with its strokes as named animations."""
    shrink_textures()
    rig.animation_data.action = None
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 1, action)
        track.mute = True
    bpy.ops.object.select_all(action="DESELECT")
    for obj in rig.children_recursive:
        if obj.type == "MESH" and obj.parent_type != "BONE":
            obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_frame_range=False, export_anim_single_armature=True,
                              export_morph=False, export_yup=True, export_skins=True,
                              export_def_bones=False, export_image_format="AUTO")


def main():
    a = args()
    clear_scene()
    basemesh, rig = build_character()
    print("RIG", rig.name if rig else None, "BONES", len(rig.data.bones) if rig else 0)
    scene = bpy.context.scene
    scene.render.fps = 120
    add_club_bone(rig)
    actions = []
    markers = {}
    for name, stroke in STROKES.items():
        action = retarget(rig, sample_bvh(stroke["bvh"], 1), name)
        markers[name] = club_track(rig, action, stroke)
        actions.append(action)
    global BALL
    view = os.environ.get("ACTION", "swing")
    rig.animation_data.action = bpy.data.actions[view]
    BALL = tuple(Vector((markers[view]["ball"][0], -markers[view]["ball"][2], markers[view]["ball"][1])))
    if a.out:
        bake_body(basemesh)
        export(rig, actions, a.out)
        with open(os.path.splitext(a.out)[0] + ".json", "w") as f:
            json.dump(markers, f, indent=1)
        print("EXPORTED", a.out)
    if a.render:
        add_club_mesh(rig, markers[view]["club_length"])
    if a.render:
        for f in [int(x) for x in a.frame.split(",")] if a.frame else [1]:
            scene.frame_set(f)
            render(a.render.replace(".png", "_%03d.png" % f), rig, f)


main()
