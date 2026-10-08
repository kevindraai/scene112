"""Original SCENE112 M5 anatomical/garment refinement, no external assets.

Operates on editable pre-rig meshes; names, rest rig and animation actions stay
owned by the original builders. Broad forms and vertex tint remain useful at
normal 3.5m conversation / 5.5m third-person distance, including vertex fallback.
"""
import math
import bpy
from mathutils import Vector


def _points(obj):
    return [(v, obj.matrix_world @ v.co) for v in obj.data.vertices]


def _reshape(obj, fn):
    inverse = obj.matrix_world.inverted()
    for vertex, point in _points(obj):
        vertex.co = inverse @ Vector(fn(point))
    obj.data.update()


def _paint(obj, fn):
    layer = obj.data.color_attributes.new(name='AuthoredMaterialVariation', type='FLOAT_COLOR', domain='POINT')
    for vertex, point in _points(obj):
        # glTF COLOR_0 uses normalized integers; Blender's active-color export
        # wraps values above one instead of clipping them. Bound authored tint.
        layer.data[vertex.index].color = (*(max(0.0, min(1.0, value)) for value in fn(point)), 1.0)
    obj.data.color_attributes.active_color = layer


def _scalp(c, root, m):
    for obj in list(c.PARTS):
        if obj.name.startswith(('HairContour', 'HairPart')):
            c.PARTS.remove(obj); bpy.data.objects.remove(obj, do_unlink=True)
    count = 32
    vertices = []
    rings = [(1.658, .118, .112), (1.748, .116, .113),
             (1.793, .099, .100), (1.833, .058, .065), (1.845, .010, .018)]
    for level, (height, rx, ry) in enumerate(rings):
        for i in range(count):
            theta = i * math.tau / count
            # Hairline rises above the forehead and follows temples/nape.
            z = height + (.067 * max(0.0, math.sin(theta)) + .017 * abs(math.cos(theta)) if level == 0 else 0)
            vertices.append((math.cos(theta)*rx, -.026+math.sin(theta)*ry, z))
    faces = []
    for level in range(len(rings)-1):
        for i in range(count):
            faces.append((level*count+i, level*count+(i+1)%count, (level+1)*count+(i+1)%count, (level+1)*count+i))
    faces.append(tuple((len(rings)-1)*count+i for i in range(count)))
    c.skin(c.k.mesh('ContinuousShortHairScalp', vertices, faces, m['hair'], root), 'Head')


def improve(c, root, m, police, ppe=False):
    _scalp(c, root, m)
    # Correct misplaced clearcoat inherited from the general vehicle helper.
    for material in m.values():
        shader=material.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Coat Weight'].default_value=0.0
        shader.inputs['Coat Roughness'].default_value=0.0
    m['hair'].node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.92
    for obj in list(c.PARTS):
        name=obj.name
        if name.startswith(('TailoredUniform','FittedJacket')):
            zs=[point.z for _,point in _points(obj)]; lo,hi=min(zs),max(zs)
            def torso(p):
                shoulder=math.exp(-((p.z-1.36)/.13)**2)
                return (p.x*(1.035+.09*shoulder), p.y*(1.06+.05*shoulder), .875+(p.z-lo)/(hi-lo)*.596)
            _reshape(obj,torso)
        elif name.startswith('TrouserSeat'):
            zs=[point.z for _,point in _points(obj)];lo,hi=min(zs),max(zs)
            _reshape(obj,lambda p:(p.x*1.09,p.y*1.10,.839+(p.z-lo)/(hi-lo)*.156))
        elif name.startswith('Neck'):
            _reshape(obj,lambda p:(p.x*1.05,p.y*1.05,1.394+(p.z-1.425)*1.52))
        elif name.startswith(('DutyBelt','BeltBuckle','UtilityPouch')):
            _reshape(obj,lambda p:(p.x*1.09,p.y*1.10,p.z))
        elif name.startswith('FittedTrouserLeg'):
            def leg(p):
                front=max(0,min(1,(p.y+.04)/.11))
                knee=math.exp(-((p.z-.525)/.10)**2)
                folds=.005*math.sin((p.z-.42)*62)*math.exp(-((p.z-.44)/.11)**2)
                return (p.x,p.y+front*(.012*knee+folds),p.z)
            _reshape(obj,leg)
        elif name.startswith(('HandPalm','Thumb','Finger')):
            _reshape(obj,lambda p:(p.x,p.y+max(0,.83-p.z)*.20,p.z))
        if name.startswith('Fingernail'):
            obj.data.materials.clear();obj.data.materials.append(m['skin'])
        # A shorter adult facial mass preserves the crown/overall height and
        # the unchanged Head pivot, while eliminating the long egg-shaped face.
        if any(g.name=='Head' for g in obj.vertex_groups):
            _reshape(obj,lambda p:(p.x*.93,p.y,1.854+(p.z-1.854)*.84))
        if name.startswith(('AdultHead','Neck','HandPalm','Finger','Thumb','Ear','SculptedNose','NostrilWing')):
            def skin_tint(p):
                cheek=math.exp(-((abs(p.x)-.055)/.037)**2-((p.z-1.687)/.043)**2)*max(0,min(1,p.y/.09))
                warmth=.018*math.sin(p.z*29+p.x*15)
                return (1.0, .98-.10*cheek+warmth, .965-.105*cheek+warmth)
            _paint(obj,skin_tint)
        elif name.startswith(('Tailored','FittedJacket','FittedTrouser','TrouserSeat','Coat reinforced')):
            def cloth_tint(p):
                wear=.045*math.sin(p.z*21+p.x*9)+.025*math.cos(p.y*37+p.z*13)
                return (.94+wear,.94+wear,.94+wear)
            _paint(obj,cloth_tint)
        elif name.startswith('ContinuousShortHair'):
            _paint(obj,lambda p:(.92+.07*math.sin(p.x*62+p.z*33),)*3)
    # Larger tailored details read at normal gameplay distance, unlike dense
    # subpixel seam tubes. These remain deforming garment geometry, no logic.
    for side,tag in [(-1,'L'),(1,'R')]:
        c.tube('UpperSleeveDoubleSeam'+tag,[(side*.230,.064,1.353),(side*.288,.061,1.269),(side*.339,.066,1.156)],.0032,m['trim'],root,tag+'UpperArm')
        c.box('ForearmReinforcement'+tag,(side*.385,.069,1.002),(.040,.012,.095),m['top'],root,tag+'ForeArm',.010)
        c.box('TrouserSidePocket'+tag,(side*.175,.004,.750),(.013,.106,.130),m['pants'],root,tag+'Thigh',.008)
        c.tube('KneeDart'+tag,[(side*.055,.074,.531),(side*.105,.090,.524),(side*.150,.073,.520)],.0027,m['trim'],root,tag+'Shin')
    if police and not ppe:
        for side in [-1,1]:
            c.box('TailoredVestFrontPanel',(side*.080,.109,1.230),(.121,.018,.206),m['pants'],root,'Chest',.012)
            c.box('ShoulderEpaulette',(side*.166,-.003,1.432),(.065,.098,.015),m['pants'],root,'Chest',.006)
        c.box('BackIdentificationPanel',(0,-.126,1.321),(.220,.008,.101),m['pants'],root,'Chest',.008)
        label=c.k.label('OriginalBack112','112',(0,-.132,1.300),.051,m['badge'],root,(math.pi/2,0,0));c.skin(label,'Chest')
        for z in [1.383,1.270]:
            c.tube('BackAmberPiping',[(-.164,-.096,z),(-.080,-.128,z),(0,-.133,z),(.080,-.128,z),(.164,-.096,z)],.006,m['accent'],root,'Chest')
        c.box('RadioDisplay',(.104,.137,1.286),(.032,.003,.024),m['badge'],root,'Chest',.002)
        c.tube('BackBeltStitch',[(-.127,-.071,.985),(0,-.105,.985),(.127,-.071,.985)],.0025,m['accent'],root,'Pelvis')
    elif not police:
        c.tube('JacketBackYoke',[(-.17,-.092,1.349),(-.085,-.12,1.323),(0,-.125,1.312),(.085,-.12,1.323),(.17,-.092,1.349)],.003,m['trim'],root,'Chest')
        for side in [-1,1]:
            c.box('RearDenimPocket',(side*.08,-.098,.848),(.075,.010,.095),m['pants'],root,'Pelvis',.008)
    if ppe:
        for side,tag in [(-1,'L'),(1,'R')]:
            c.box('PPEKneeReinforcement'+tag,(side*.105,.083,.491),(.102,.017,.121),m['trim'],root,tag+'Shin',.015)
            c.box('GloveKnucklePanel'+tag,(side*.418,.077,.851),(.061,.010,.029),m['trim'],root,tag+'Hand',.007)
        c.tube('PPECoatBackHem',[(-.12,-.086,1.015),(0,-.108,1.015),(.12,-.086,1.015)],.003,m['accent'],root,'Spine')
    # glTF exports vertex color only when the material explicitly consumes it.
    # Give every joined component white defaults so added hardware stays intact.
    materials=set()
    for obj in c.PARTS:
        if obj.data.color_attributes.get('AuthoredMaterialVariation') is None:
            _paint(obj,lambda _p:(1.0,1.0,1.0))
        materials.update(obj.data.materials)
    for material in materials:
        nodes=material.node_tree.nodes; links=material.node_tree.links
        shader=nodes.get('Principled BSDF'); base=shader.inputs['Base Color']
        previous=base.links[0].from_socket if base.is_linked else None
        old_color=tuple(base.default_value)
        vertex=nodes.new('ShaderNodeVertexColor'); vertex.layer_name='AuthoredMaterialVariation'
        if previous:
            mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1.0
            links.new(previous,mix.inputs[1]);links.new(vertex.outputs['Color'],mix.inputs[2]);links.new(mix.outputs[0],base)
        else:
            # Constant-color material: store the intended color in COLOR_0.
            # This is also the direct editable Blender shading input.
            for obj in c.PARTS:
                if material not in list(obj.data.materials):continue
                layer=obj.data.color_attributes['AuthoredMaterialVariation']
                for value in layer.data:
                    tint=value.color
                    value.color=(tint[0]*old_color[0],tint[1]*old_color[1],tint[2]*old_color[2],1.0)
            links.new(vertex.outputs['Color'],base)
