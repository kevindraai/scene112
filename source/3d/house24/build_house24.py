"""Playable ground-floor Huis24 visual shell, matching authored Noorderkade terrace.
Original SCENE112 source, no exported physics/VFX. DoorPivot is a real hinge.
"""
from pathlib import Path
import math
import sys
import json
import bpy
from mathutils import Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
import assetkit as k
import street_shape as s
import street_textures as t

BASE=Path(__file__).resolve().parents[3]
TEX=BASE/'assets/textures/house24'
OUT=BASE/'assets/models/house24'


def E(name,at=(0,0,0),parent=None):
    obj=k.empty(name,s.point(at))
    if parent:obj.parent=parent;obj.matrix_parent_inverse=Matrix.Identity(4)
    bpy.context.view_layer.update()
    return obj


def local(obj,parent):
    obj.parent=parent;obj.matrix_parent_inverse=Matrix.Identity(4)
    bpy.context.view_layer.update()
    return obj


def B(name,at,size,mat,parent,bevel=.015):return local(s.box(name,at,size,mat,bevel),parent)
def M(name,vertices,faces,mat,parent):return local(s.mesh(name,vertices,faces,mat),parent)
def T(name,start,end,radius,mat,parent,segments=16):return local(s.tube(name,start,end,radius,mat,segments),parent)


def S(name,at,size,mat,parent):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=14,radius=1,location=s.point(at))
    obj=bpy.context.object;obj.name=name;obj.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:poly.use_smooth=True
    s.unwrap(obj)
    return local(obj,parent)


def label(name,text,at,size,mat,parent):
    return k.label(name,text,s.point(at),size,mat,parent,(math.pi/2,0,math.pi))


def join(root,name):
    meshes=[obj for obj in root.children if obj.type=='MESH']
    if not meshes:return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.object.name=name


def combine_direct(root,name,exclude=()):
    meshes=[obj for obj in root.children if obj.type=='MESH' and obj.name not in exclude]
    if not meshes:return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();bpy.context.object.name=name


def shell_window(parent,x,y,m,upper=False,openable=False):
    width=1.6;height=1.45;z=-3.52
    if upper:B('Upper bedroom recess',(x,y,z+.23),(width,height,.04),m['dark'],parent,0)
    for dx in [-.8,.8]:
        B('Window masonry reveal',(x+dx,y,z+.08),(.12,1.65,.32),m['brick'],parent)
        B('Cream outer window stile',(x+dx,y,z-.05),(.095,1.57,.13),m['cream'],parent)
    for dy in [-.725,.725]:B('Cream outer window rail',(x,y+dy,z-.05),(1.74,.09,.13),m['cream'],parent)
    B('Concrete window sill',(x,y-.815,z-.11),(1.90,.12,.35),m['stone'],parent)
    B('Window lintel',(x,y+.835,z-.005),(1.82,.12,.20),m['stone'],parent)
    pane=parent
    if openable:pane=E('WindowPivot',(x-.72,y-.65,z-.025),parent)
    cx=.72 if openable else x;cy=.65 if openable else y;cz=0 if openable else z+.025
    B('WindowLeaf' if openable else 'Glazed panes',(cx,cy,cz),(1.45,1.30,.025),m['glass'],pane,0)
    for dx in [-.735,.735]:B('Casement stile',(cx+dx,cy,cz-.02),(.055,1.34,.07),m['cream'],pane,.005)
    for dy in [-.65,.65]:B('Casement rail',(cx,cy+dy,cz-.02),(1.50,.045,.07),m['cream'],pane,.005)
    B('Window mullion',(cx,cy,cz-.04),(.045,1.30,.09),m['cream'],pane,.005)
    B('Window transom',(cx,cy+.35,cz-.04),(1.45,.04,.09),m['cream'],pane,.005)
    if openable:join(pane,'WindowLeaf')
    for side in [-1,1]:
        B('Linen curtain fold',(x+side*.62,y,z+.17),(.20,1.20,.045),m['linen'],parent,.015)


def build_shell(root,m):
    shell=E('MasonryShell',parent=root)
    # Perimeter foundation: no full solid plinth across the playable room/door.
    for x,width in [(-2.03,2.74),(2.03,2.74)]:
        B('Split front brick plinth',(x,.34,-3.35),(width,.68,.30),m['brick'],shell,.025)
        B('Ground below-window course',(x,.845,-3.35),(width,.33,.30),m['brick'],shell,.010)
    B('Rear plinth',(0,.34,3.35),(6.8,.68,.30),m['brick'],shell,.02)
    B('Rear masonry',(0,3.04,3.35),(6.8,4.72,.30),m['brick'],shell,.01)
    for side in [-1,1]:
        B('Side plinth',(side*3.25,.34,0),(.30,.68,7),m['brick'],shell,.02)
        B('Side masonry',(side*3.25,3.04,0),(.30,4.72,7),m['brick'],shell,.01)
    for bottom,top in [(2.48,3.24),(4.74,5.4)]:B('Facade masonry course',(0,(bottom+top)/2,-3.35),(6.8,top-bottom,.30),m['brick'],shell,.010)
    for x,width in [(-2.94,.92),(-.77,.22),(.77,.22),(2.94,.92)]:
        B('Ground brick pier',(x,1.72,-3.35),(width,1.44,.30),m['brick'],shell,.010)
    B('Brick above doorway',(0,2.355,-3.35),(1.32,.25,.30),m['brick'],shell,.010)
    for x,width in [(-2.94,.92),(0,1.76),(2.94,.92)]:B('Upper brick pier',(x,3.99,-3.35),(width,1.50,.30),m['brick'],shell,.010)
    # Door opening is1.32m masonry /1.215m clear between casing inner edges.
    for x in [-.655,.655]:B('Door casing',(x,1.16,-3.58),(.095,2.32,.16),m['cream'],shell,.008)
    B('Door casing lintel',(0,2.31,-3.53),(1.40,.10,.24),m['cream'],shell,.008)
    B('Level door threshold',(0,.018,-3.51),(1.215,.025,.48),m['stone'],shell,.004)
    for x in [-1.68,1.68]:
        shell_window(shell,x,1.74,m,openable=x<0)
        shell_window(shell,x,4.0,m,upper=True)
    # The street's recognizable pitched clay roof and front/rear gables stay intact.
    for z in [-3.36,3.36]:M('Gable brickwork',[(-3.4,5.4,z),(3.4,5.4,z),(0,7.05,z)],[(0,2,1) if z<0 else (0,1,2)],m['brick'],shell)
    for side in [-1,1]:
        M('Clay tile roof',[(0,7.12,-3.75),(0,7.12,3.75),(side*3.65,5.33,3.75),(side*3.65,5.33,-3.75)],[(0,1,2,3) if side>0 else (3,2,1,0)],m['roof'],shell)
        T('Zinc rain gutter',(side*3.65,5.29,-3.74),(side*3.65,5.29,3.74),.055,m['metal'],shell)
        T('Downpipe',(side*3.31,5.25,-3.54),(side*3.31,.08,-3.54),.036,m['metal'],shell)
    for z in [i*.42-3.55 for i in range(18)]:T('Clay ridge cap',(0,7.12,z),(0,7.12,z+.40),.12,m['roof'],shell,12)
    B('Chimney brickwork',(2,6.3,1.8),(.70,1.75,.80),m['brick'],shell,.025)
    B('Chimney stone crown',(2,7.20,1.8),(.82,.12,.92),m['stone'],shell)
    for z in [1.62,1.99]:T('Chimney pot',(2,7.24,z),(2,7.50,z),.11,m['roof'],shell)
    B('Eaves fascia',(0,5.38,-3.68),(7.20,.16,.14),m['cream'],shell)
    # Floor surface at .02, and an actual readable plaster-lined living space.
    floor=E('GroundFloor',parent=root)
    B('WalkableFloor',(0,-.005,0),(6.2,.050,6.4),m['wood'],floor,.004)
    B('GroundFloorCeiling',(0,2.805,0),(6.2,.10,6.4),m['plaster'],floor,.004)
    for side in [-1,1]:B('Interior side plaster',(side*3.075,1.39,0),(.035,2.73,6.38),m['plaster'],floor,.005)
    B('Interior rear plaster',(0,1.39,3.185),(6.17,2.73,.035),m['plaster'],floor,.005)
    # Skirting stays on perimeter and also leaves the front door gap open.
    for side in [-1,1]:B('Oak skirting',(side*3.042,.073,0),(.027,.105,6.30),m['wood'],floor,.004)
    B('Rear skirting',(0,.073,3.151),(6.08,.105,.027),m['wood'],floor,.004)
    for x,width in [(-2.00,2.63),(2.00,2.63)]:B('Front skirting',(x,.073,-3.155),(width,.105,.027),m['wood'],floor,.004)
    # A true left hinge; −90° about GodotY opens inward along the west hallway side.
    door=E('DoorPivot',(-.59,0,-3.555),root)
    B('DoorLeaf',(.59,1.145,0),(1.18,2.24,.075),m['navy'],door,.018)
    for y in [.45,1.01,1.65]:B('Recessed oak door panel',(.59,y,-.049),(.94,.41,.018),m['inset'],door,.012)
    B('Letter slot',(.59,.89,-.060),(.28,.065,.020),m['metal'],door,.006)
    T('Door handle',(.985,1.11,-.070),(.858,1.11,-.070),.014,m['metal'],door)
    T('Inside handle',(.985,1.11,.059),(.858,1.11,.059),.014,m['metal'],door)
    for y in [.25,1.14,2.03]:T('Door hinge',(.008,y-.05,.0),(.008,y+.05,.0),.013,m['metal'],door,12)
    join(door,'DoorLeaf')
    B('House number plaque',(1.045,1.65,-3.539),(.23,.16,.028),m['navy'],shell,.008)
    label('House24Number','24',(1.045,1.615,-3.558),.092,m['cream'],shell)
    return shell,floor


def livingroom(root,m):
    living=E('LivingRoom',parent=root)
    sofa=E('LivingSofa',(-2.07,0,-.86),living)
    B('Sofa oak base',(0,.22,0),(1.80,.26,.79),m['wood'],sofa,.045)
    B('Sofa upholstery back',(0,.66,.32),(1.87,.75,.22),m['fabric'],sofa,.055)
    for x in [-.95,.95]:B('Sofa rounded arm',(x,.54,0),(.21,.51,.87),m['fabric'],sofa,.06)
    for x in [-.47,.47]:B('Sofa seat cushion',(x,.44,-.045),(.90,.17,.63),m['fabric'],sofa,.06)
    for x in [-.39,.39]:
        pillow=B('Loose sofa cushion',(x,.81,.148),(.52,.34,.11),m['linen'],sofa,.06)
        pillow.rotation_euler.x=.11
    for x in [-.72,.72]:
        for z in [-.27,.27]:T('Sofa foot',(x,.02,z),(x,.17,z),.034,m['dark'],sofa)
    join(sofa,'LivingSofaSurface')
    front=E('FuelFront',(0,0,-1.6),living)
    B('CoffeeTableTop',(0,.425,0),(.83,.045,.60),m['wood'],front,.028)
    for x in [-.33,.33]:
        for z in [-.21,.21]:T('Coffee table leg',(x,.02,z),(x,.40,z),.025,m['wood'],front)
    B('Closed document folder',(.14,.461,.06),(.25,.012,.21),m['inset'],front,.006)
    S('Ceramic cup',(-.24,.494,-.04),(.043,.060,.043),m['cream'],front)
    join(front,'FuelFrontSurface')
    sideboard=E('LivingSideboard',(2.44,0,-1.03),living)
    B('Sideboard oak body',(0,.45,0),(.91,.78,.48),m['wood'],sideboard,.022)
    for x in [-.21,.21]:
        B('Sideboard door',(x,.45,-.255),(.405,.66,.025),m['cream'],sideboard,.010)
        T('Sideboard handle',(x+.12,.45,-.285),(x+.12,.55,-.285),.006,m['metal'],sideboard)
    S('Indoor planter',(-.13,.889,0),(.093,.080,.093),m['cream'],sideboard)
    for x,z in [(-.14,-.03),(-.07,.01),(-.17,.03)]:T('Plant stem',(x,.93,z),(x,.93+.26,z+.035),.012,m['green'],sideboard,8)
    join(sideboard,'LivingSideboardSurface')
    E('VictimAnchor',(-.8,0,-1.8),root)
    E('CellFrontAnchor',(0,.55,-1.6),root)
    return living


def kitchen(root,m):
    room=E('Kitchen',parent=root)
    units=E('KitchenUnits',(-2.41,0,2.50),room)
    B('Base cabinet',(0,.445,0),(1.20,.85,.67),m['cream'],units,.018)
    B('Dark worktop',(0,.89,0),(1.27,.045,.73),m['dark'],units,.017)
    for x in [-.29,.29]:
        B('Kitchen cupboard front',(x,.46,-.353),(.55,.72,.026),m['cream'],units,.010)
        T('Cupboard grip',(x+.18,.53,-.385),(x+.18,.64,-.385),.007,m['metal'],units)
    B('Sink inset',(.28,.924,.08),(.46,.014,.42),m['metal'],units,.017)
    B('Sink hollow visual',(.28,.932,.08),(.35,.010,.31),m['dark'],units,.018)
    T('Tap upright',(.48,.91,.22),(.48,1.13,.22),.018,m['metal'],units)
    T('Tap spout',(.48,1.13,.22),(.32,1.13,.22),.018,m['metal'],units)
    B('Tile backsplash',(-.605,1.27,0),(.023,.66,.68),m['tile'],units,.005)
    join(units,'KitchenUnitsSurface')
    fridge=E('KitchenFridge',(-2.58,0,1.34),room)
    B('Fridge cabinet',(0,.77,0),(.72,1.52,.62),m['cream'],fridge,.038)
    for y,height in [(1.28,.40),(.57,.92)]:
        B('Fridge front',(0,y,-.326),(.66,height,.035),m['cream'],fridge,.018)
        T('Fridge grip',(.23,y-.14,-.374),(.23,y+.13,-.374),.008,m['metal'],fridge)
    join(fridge,'KitchenFridgeSurface')
    # Neutral appliance/cable context: not an authored verdict on the eventual cause.
    appliance=E('FuelOrigin',(-1.8,0,1.8),room)
    B('OriginAppliance',(0,.29,0),(.43,.53,.39),m['metal'],appliance,.042)
    B('Appliance grille',(0,.285,-.202),(.33,.32,.014),m['dark'],appliance,.015)
    for y in [.175,.215,.255,.295,.335,.375,.415]:B('Appliance vent',(0,y,-.214),(.28,.017,.006),m['metal'],appliance,.003)
    S('Appliance control',(.12,.485,-.10),(.020,.016,.020),m['dark'],appliance)
    for x in [-.155,.155]:B('Appliance foot',(x,.046,0),(.072,.052,.34),m['dark'],appliance,.008)
    join(appliance,'FuelOriginSurface')
    outlet=E('OriginOutlet',(-3.026,.82,2.31),room)
    B('OutletFace',(0,0,0),(.045,.16,.15),m['cream'],outlet,.012)
    for z in [-.023,.023]:S('Socket recess',(.028,.002,z),(.012,.010,.010),m['dark'],outlet)
    join(outlet,'OriginOutletSurface')
    # Surface cable remains a visual artifact; root owns electrical hypotheses.
    T('Power lead A',(-3.00,.76,2.31),(-2.96,.065,2.31),.006,m['dark'],room,12)
    T('Power lead B',(-2.96,.065,2.31),(-2.22,.044,2.05),.006,m['dark'],room,12)
    T('Power lead C',(-2.22,.044,2.05),(-1.63,.12,1.95),.006,m['dark'],room,12)
    E('CellOriginAnchor',(-1.8,.55,1.8),root)
    return room


def shelves(root,m):
    group=E('FuelSide',(1.8,0,1.7),root)
    B('Shelf back',(0,.93,.18),(1.02,1.82,.055),m['wood'],group,.012)
    for x in [-.54,.54]:B('Shelf side',(x,.93,0),(.055,1.82,.44),m['wood'],group,.012)
    for y in [.12,.63,1.12,1.76]:B('Shelf plank',(0,y,0),(1.08,.045,.45),m['wood'],group,.012)
    for i in range(7):
        book=B('Shelf book',(-.41+i*.092,.84,-.06),(.076,.32,.26),m['linen'] if i%2 else m['inset'],group,.004)
        book.rotation_euler.y=(i%3-1)*.025
    for x in [-.24,.24]:B('Stored paper box',(x,.324,-.018),(.40,.34,.31),m['linen'],group,.020)
    join(group,'FuelSideSurface')
    E('CellSideAnchor',(1.8,.55,1.7),root)


def build():
    k.clean();TEX.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    for kind,seed in [('brick',112),('roof',115),('wood',116)]:
        for suffix,pixels in zip(['albedo','normal','roughness'],t.maps(kind,seed)):t.png(TEX/(kind+'_'+suffix+'.png'),pixels)
    root=E('BurningHouse24')
    m={'brick':s.material('Noorderkade red brick PBR',(.5,.2,.1),texture='brick'),
       'roof':s.material('Clay roof tiles PBR',(.5,.2,.1),texture='roof'),
       'wood':s.material('Weathered oak PBR',(.5,.3,.1),texture='wood'),
       'cream':k.material('Painted timber frames',(.78,.75,.64),.54),
       'stone':k.material('Cast concrete sills',(.50,.52,.48),.91),
       'navy':k.material('Navy powder coating',(.022,.060,.085),.46,.12),
       'inset':k.material('Painted inset panels',(.013,.035,.043),.60),
       'metal':k.material('Weathered zinc metal',(.30,.34,.35),.34,.82),
       'dark':k.material('Recess and rubber',(.012,.016,.017),.91),
       'glass':k.material('Window reflection',(.63,.75,.79),.12,.03,alpha=.18),
       'linen':k.material('Natural linen curtains',(.53,.51,.44),.98,0,TEX,'fabric'),
       'fabric':k.material('Livingroom original cloth',(.13,.19,.19),.92,0,TEX,'fabric'),
       'plaster':k.material('Interior matte plaster',(.67,.65,.58),.94,0,TEX,'paint'),
       'tile':k.material('Kitchen ceramic tile',(.48,.50,.44),.47,0,TEX,'paint'),
       'green':k.material('Indoor plant leaf',(.09,.16,.055),.84)}
    shell,floor=build_shell(root,m);livingroom(root,m);room=kitchen(root,m);shelves(root,m)
    combine_direct(shell,'MasonryShellSurface')
    combine_direct(floor,'InteriorLiningSurface',('WalkableFloor','GroundFloorCeiling'))
    combine_direct(room,'PowerLeadSurface')
    m['plaster'].node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=0.0
    E('EntranceAnchor',(0,0,-4),root)
    k.finish(root,OUT,'burning_house24',12,7.5)
    metadata={'world_origin':[-2,0,48],'footprint_m':[6.8,7.0],'floor_top_y_m':.02,'door_clear_width_m':1.215,
        'door_clear_height_m':2.24,'door_pivot':[-.59,0,-3.555],'door_open_godot_y_radians':-math.pi/2,
        'interior_ceiling_bottom_y_m':2.755,'outer_walls':{'west':[-3.25,2.70,0,.30,5.40,7],'east':[3.25,2.70,0,.30,5.40,7],'rear':[0,2.70,3.35,6.8,5.40,.30]},
        'nodes':['DoorPivot','DoorLeaf','WindowPivot','WindowLeaf','GroundFloor','WalkableFloor','FuelFront','FuelOrigin','FuelSide',
                 'OriginOutlet','CellFrontAnchor','CellOriginAnchor','CellSideAnchor','VictimAnchor','EntranceAnchor'],
        'no_collision_or_vfx':True,'physical_owner':'Root FireSite','cause_verdict_authored':False}
    (OUT/'burning_house24_layout.json').write_text(json.dumps(metadata,indent=2))
    print('SCENE112_HOUSE24_SOURCE_READY',json.dumps(metadata),flush=True)


build()
