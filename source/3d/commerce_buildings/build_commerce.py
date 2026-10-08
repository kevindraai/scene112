"""Original closed bakery/workshop shells, replacing existing blockout renderers.

No exported physics, new geography, interior gameplay, agency/real business brand.
Local metres, front -Z/up+Y; placement yaw handles old workshop +Z frontage.
"""
from pathlib import Path
import sys,math,json,hashlib
import bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import assetkit as k
import street_surface_fields as f
BASE=Path(__file__).resolve().parents[3]
TEX=BASE/'assets/textures/commerce_buildings'
OUT=BASE/'assets/models/commerce_buildings'
k.LOW_DETAIL=True

def point(at):return (at[0],-at[2],at[1])
def group(root,name):obj=k.empty(name);k.parent(obj,root);return obj

def uv_metres(obj,tile=2.1):
    bpy.context.view_layer.update()
    for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
    uv=obj.data.uv_layers.new(name='Physical surface metres');obj.data.uv_layers.active_index=0;uv.active_render=True
    for face in obj.data.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]));indices=[i for i in range(3)if i!=axis]
        for index in face.loop_indices:
            at=obj.matrix_world@obj.data.vertices[obj.data.loops[index].vertex_index].co
            uv.data[index].uv=(at[indices[0]]/tile,at[indices[1]]/tile)

def tint(obj,colour=(1,1,1)):
    attr=obj.data.color_attributes.new(name='SurfaceTint',type='FLOAT_COLOR',domain='CORNER')
    for entry in attr.data:entry.color=(*colour,1)
    obj.data.color_attributes.active_color=attr;obj.data.color_attributes.render_color_index=0
    return obj

def B(root,name,at,size,mat,bevel=.006,colour=(1,1,1)):
    obj=k.box(name,point(at),(size[0],size[2],size[1]),mat,root,bevel)
    uv_metres(obj);return tint(obj,colour)
def M(root,name,verts,faces,mat,colour=(1,1,1)):
    obj=k.mesh(name,[point(v)for v in verts],faces,mat,root);uv_metres(obj);return tint(obj,colour)
def T(root,name,points,radius,mat,colour=(1,1,1)):
    obj=k.tube(name,[point(v)for v in points],radius,mat,root);uv_metres(obj);return tint(obj,colour)
def ELL(root,name,at,size,mat,colour):
    obj=k.sphere(name,point(at),(size[0],size[2],size[1]),mat,root,segments=16,rings=8);uv_metres(obj,.25);return tint(obj,colour)
def join(root,name):
    meshes=[obj for obj in root.children if obj.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=name
    attr=obj.data.color_attributes
    if attr.get('SurfaceTint') is not None:
        for entry in list(attr):
            if entry.name!='SurfaceTint':attr.remove(entry)
        attr.active_color=attr.get('SurfaceTint');attr.render_color_index=0
    obj.select_set(False)

def textured(name,stem,values,metallic):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Metallic'].default_value=metallic
    for suffix,pixels,socket in zip(['albedo','normal','roughness'],values,['Base Color','Normal','Roughness']):
        file=TEX/(stem+'_'+suffix+'.png');f.png(file,pixels)
        image=bpy.data.images.load(str(file),check_existing=True)
        if suffix!='albedo':image.colorspace_settings.name='Non-Color'
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        if suffix=='normal':
            normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.65
            mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],shader.inputs[socket])
        elif suffix=='albedo':
            color=mat.node_tree.nodes.new('ShaderNodeVertexColor');mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
            mat.node_tree.links.new(node.outputs['Color'],mix.inputs[1]);mat.node_tree.links.new(color.outputs['Color'],mix.inputs[2]);mat.node_tree.links.new(mix.outputs[0],shader.inputs[socket])
        else:mat.node_tree.links.new(node.outputs['Color'],shader.inputs[socket])
    return mat

def materials():
    TEX.mkdir(parents=True,exist_ok=True)
    brick=textured('Commerce original Dutch masonry','commerce_masonry',f.maps('brick',112),0)
    rng=np.random.default_rng(11246);y,x=np.mgrid[:512,:512]/512
    noise=rng.random((512,512));broad=f.smooth_noise(rng,12);fine=f.smooth_noise(rng,64)
    # New original periodic brushed/coated sheet with run-off/weather stains.
    stripe=.5+.5*np.sin(x*math.pi*64+broad*2)
    stain=np.maximum(0,f.smooth_noise(rng,32)-.48)*.12
    tone=.88+broad*.06+noise*.02-stain
    height= stripe*.0003+fine*.00018
    dx=(np.roll(height,-1,1)-np.roll(height,1,1))*512/4.2;dy=(np.roll(height,-1,0)-np.roll(height,1,0))*512/4.2
    normal=np.stack([-dx,-dy,np.ones_like(height)],2);normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    steel=textured('Commerce aged coated sheet metal','commerce_sheet',(tone[:,:,None]*np.array([190,194,189]),(normal*.5+.5)*255,(.72+fine*.10+stain)*255),.08)
    # Neutral painted material supports original vertex-colour shop accents/props.
    tone=.92+broad*.06+noise*.02
    paint=textured('Commerce powder paint and decorative props','commerce_paint',(tone[:,:,None]*np.array([235,234,229]),(normal*.5+.5)*255,(.58+fine*.15)*255),0)
    glass=k.material('Commerce original window glass',(.60,.72,.77),.11,.04,alpha=.23)
    return {'brick':brick,'steel':steel,'paint':paint,'glass':glass}

def framing(root,x,y,z,w,h,m):
    for edge in [-1,1]:
        B(root,'Metal glazing stile',(x+edge*w/2,y,z),( .075,h+.07,.14),m['steel'],.004,(.19,.30,.29))
        B(root,'Metal glazing rail',(x,y+edge*h/2,z),(w+.08,.075,.14),m['steel'],.004,(.19,.30,.29))
    B(root,'Recessed shop glazing',(x,y,z+.035),(w-.085,h-.085,.014),m['glass'],0)
    B(root,'Cast masonry sill',(x,y-h/2-.065,z+.035),(w+.19,.10,.26),m['paint'],.005,(.69,.66,.58))

def bakery():
    k.clean();m=materials();root=k.empty('BakeryShell');shell=group(root,'BakeryFacade');roof=group(root,'BakeryRoof');display=group(root,'WindowDisplayClosed')
    # Closed existing footprint, lower Dutch brick plinth and split real glazing.
    for side in [-1,1]:B(shell,'Bakery side Dutch masonry',(side*6.38,2,0),(.24,4,9),m['brick'])
    B(shell,'Bakery rear Dutch masonry',(0,2,4.38),(13,4,.24),m['brick'])
    B(shell,'Bakery upper facade brick',(0,3.62,-4.38),(13,.76,.24),m['brick'])
    B(shell,'Bakery below-shopwindow plinth',(0,.38,-4.38),(13,.76,.24),m['brick'])
    for x,w in [(-6.1,.8),(-1.575,.65),(2.825,1.45),(5.8,1.4)]:B(shell,'Shop masonry pier',(x,2.0,-4.38),(w,2.5,.24),m['brick'])
    for x,w in [(-3.80,3.8),(.35,3.2)]:
        framing(shell,x,1.87,-4.495,w,2.12,m)
        B(shell,'Shop window horizontal division',(x,2.42,-4.54),(w-.09,.035,.055),m['steel'],.003,(.2,.3,.29))
    B(shell,'Original sign fascia retaining label',(0,3.10,-4.50),(12,.39,.18),m['paint'],.007,(.15,.28,.27))
    # Actual closed framed door, no pivot/animation/interaction promise.
    door=group(root,'ClosedFrontDoor')
    B(door,'Closed shop door leaf',(4.35,1.20,-4.51),(1.17,2.40,.09),m['paint'],.011,(.15,.28,.27))
    for x in [3.72,4.98]:B(door,'Closed door jamb',(x,1.25,-4.52),(.10,2.50,.17),m['steel'],.005,(.22,.31,.3))
    B(door,'Closed door lintel',(4.35,2.48,-4.52),(1.36,.09,.17),m['steel'],.005,(.22,.31,.3))
    B(door,'Closed door upper glazing',(4.35,1.61,-4.564),(.81,1.24,.016),m['glass'],0)
    T(door,'Shop door pull',[(4.77,.92,-4.60),(4.77,1.38,-4.60)],.014,m['steel'])
    B(door,'Door kick plate',(4.35,.19,-4.56),(.99,.25,.018),m['steel'],.005)
    # Existing world ShopAwning remains visible; only add supporting brackets.
    for x in [-5.65,0,5.65]:T(roof,'Triangular canopy bracket',[(x,3.22,-4.49),(x,3.22,-5.65),(x,3.52,-4.49)],.024,m['steel'],(.20,.31,.30))
    B(roof,'Flat shop roof',(0,4.015,0),(13,.08,9),m['steel'],.007)
    for side in [-1,1]:B(roof,'Shop coping strip',(side*6.42,4.07,0),(.16,.12,9),m['steel'],.005)
    for z in [-4.42,4.42]:B(roof,'Shop coping strip',(0,4.07,z),(13,.12,.16),m['steel'],.005)
    T(shell,'Shop zinc downpipe',[(6.43,3.94,4.42),(6.43,.10,4.42)],.035,m['steel'])
    # Shallow etalage objects only, physically blocked by existing Bakery box.
    for x,w in [(-3.8,3.6),(.35,3.0)]:
        B(display,'Window display back panel',(x,1.75,-3.74),(w,1.85,.065),m['paint'],.007,(.65,.54,.40))
        B(display,'Closed display counter',(x,.88,-4.08),(w,.12,.64),m['paint'],.012,(.45,.28,.13))
        for y in [1.13,1.52]:B(display,'Bakery display tray',(x,y,-4.06),(w-.22,.025,.45),m['paint'],.005,(.30,.22,.14))
        for i in range(4):
            at=(x+(i-1.5)*.53,1.64,-4.07)
            ELL(display,'Original small bread loaf',at,(.21,.12,.15),m['paint'],(.85,.58,.26))
            for cut in [-.07,.04]:B(display,'Baked loaf score',(at[0]+cut,1.747,-4.07),(.032,.011,.14),m['paint'],.002,(.40,.24,.09))
    join(shell,'BakeryFacadeSurface');join(roof,'BakeryRoofSurface');join(display,'BakeryDisplaySurface');join(door,'BakeryClosedDoorSurface')
    audit(root,'bakery_shell');k.finish(root,OUT,'bakery_shell',18,4.2)

def workshop():
    k.clean();m=materials();root=k.empty('WorkshopShell');shell=group(root,'WorkshopFacade');roof=group(root,'WorkshopRoof');door=group(root,'ClosedLoadingDoor')
    B(shell,'Workshop rear brick plinth',(0,.68,7.86),(24,1.36,.28),m['brick'])
    B(shell,'Workshop rear aged steel',(0,4.48,7.86),(24,6.24,.28),m['steel'],.007,(.56,.69,.69))
    for side in [-1,1]:
        B(shell,'Workshop side brick plinth',(side*11.86,.68,0),(.28,1.36,16),m['brick'])
        B(shell,'Workshop side aged steel',(side*11.86,4.48,0),(.28,6.24,16),m['steel'],.006,(.56,.69,.69))
        for z in [i*.64-7.68 for i in range(25)]:B(shell,'Vertical side metal rib',(side*12.012,4.48,z),(.036,6.20,.035),m['steel'],.002,(.50,.64,.64))
        T(shell,'Factory rain downpipe',[(side*12.27,7.68,-7.90),(side*12.27,.14,-7.90)],.053,m['steel'])
    for x,w in [(-7.25,9.5),(8.25,7.5)]:
        B(shell,'Workshop front brick plinth',(x,.68,-7.86),(w,1.36,.28),m['brick'])
        B(shell,'Workshop front aged steel',(x,4.48,-7.86),(w,6.24,.28),m['steel'],.006,(.56,.69,.69))
    B(shell,'Loading portal upper steel',(1,6.14,-7.86),(7,2.92,.28),m['steel'],.006,(.56,.69,.69))
    for x in [i*.64-11.52 for i in range(37)]:
        if -2.5<x<4.5:continue
        B(shell,'Vertical facade metal rib',(x,4.48,-8.012),(.036,6.20,.035),m['steel'],.002,(.50,.64,.64))
    # Sign plate at localx0 maps to old worldcenter24, y6.3,z-35.9.
    B(shell,'Workshop original-label sign housing',(0,6.30,-8.045),(19,.65,.08),m['paint'],.006,(.18,.24,.25))
    B(door,'Closed metal loading shutter',(1,2.30,-8.014),(7,4.60,.075),m['steel'],.009,(.78,.79,.74))
    for y in [i*.16+.08 for i in range(29)]:B(door,'Rolled shutter horizontal slat',(1,y,-8.068),(6.85,.028,.025),m['steel'],.002,(.57,.60,.57))
    for x in [-2.55,4.55]:B(door,'Recessed loading guide rail',(x,2.38,-8.08),(.10,4.76,.14),m['steel'],.005)
    B(door,'Shutter bottom weather seal',(1,.045,-8.080),(6.89,.085,.045),m['paint'],.005,(.05,.07,.06))
    T(door,'Loading shutter manual grip',[(.65,.98,-8.103),(1.35,.98,-8.103)],.017,m['steel'])
    # Existing roof envelope25x17, with a shallow profiled original sheet top.
    M(roof,'Workshop roof slope',[(-12.5,7.70,-8.5),(12.5,7.70,-8.5),(12.5,7.82,8.5),(-12.5,7.82,8.5)],[(0,3,2,1)],m['steel'],(.37,.45,.45))
    B(roof,'Original warehouse roof underside',(0,7.65,0),(25,.10,17),m['paint'],0,(.09,.12,.12))
    for x in [i*.7-12.25 for i in range(36)]:T(roof,'Long roof sheet seam',[(x,7.718,-8.47),(x,7.838,8.47)],.009,m['steel'])
    for z in [-8.47,8.47]:T(roof,'Factory zinc gutter',[(-12.44,7.69,z),(12.44,7.69,z)],.058,m['steel'])
    for x in [-7,6]:
        B(roof,'Original extraction curb',(x,7.98,2.4),(1.18,.37,1.26),m['steel'],.019)
        B(roof,'Extraction vent hood',(x,8.29,2.4),(1.35,.21,1.42),m['steel'],.02,(.62,.65,.61))
        for z in [2.0,2.20,2.40,2.60,2.80]:B(roof,'Roof ventilation louver',(x,8.07,z),(1.11,.10,.045),m['paint'],.003,(.12,.16,.16))
    join(shell,'WorkshopFacadeSurface');join(roof,'WorkshopRoofSurface');join(door,'WorkshopClosedLoadingSurface')
    audit(root,'workshop_shell');k.finish(root,OUT,'workshop_shell',32,8.5)

def audit(root,name):
    meshes=[obj for obj in root.children_recursive if obj.type=='MESH'];mats={m.name for obj in meshes for m in obj.data.materials}
    tris=sum(sum(len(p.vertices)-2 for p in obj.data.polygons)for obj in meshes)
    assert tris<=20000,(name,tris);assert len(mats)<=4,(name,mats)
    print('SCENE112_COMMERCE_BUDGET',name,tris,len(mats),flush=True)

def build():
    OUT.mkdir(parents=True,exist_ok=True);bakery();workshop()
    metadata={'units':'metres','up':'+Y','local_front':'-Z','no_exported_physics':True,'no_new_interiors_or_gameplay':True,
      'bakery':{'world_origin':[46,0,31],'yaw':0,'body_footprint':[13,9],'body_height':4,'awning_footprint':[12,2],'preserve_existing_awning':True,
        'closed_door_center_local':[4.35,1.2,-4.51],'front_world_z':26.5,'preserve_sign_world':[46,3.1,26.38],
        'hide_old_render_nodes':['Bakery (MeshInstance descendants only; keep StaticBody)','ShopWindow']},
      'workshop':{'world_origin':[24,0,-44],'yaw':math.pi,'body_footprint':[24,16],'body_height':7.6,'roof_envelope':[25,17],
        'closed_loading_center_local':[1,2.3,-8.014],'front_world_z':-36,'preserve_sign_world':[24,6.3,-35.9],
        'hide_old_render_nodes':['Warehouse (MeshInstance descendants only; keep StaticBody)','WarehouseRoof','LoadingDoor','LoadingDoorSeam instances at x23,z-35.9,y=.8/1.6/2.4/3.2/4']}}
    (OUT/'commerce_integration.json').write_text(json.dumps(metadata,indent=2)+'\n')
    records=[]
    for file in sorted(TEX.glob('*.png')):records.append({'file':file.name,'resolution':[512,512],'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'author':'Original SCENE112','source':'source/3d/commerce_buildings/build_commerce.py / street_surface_fields.py','license':'Project private/proprietary'})
    (TEX/'manifest.json').write_text(json.dumps(records,indent=2)+'\n')
build()
