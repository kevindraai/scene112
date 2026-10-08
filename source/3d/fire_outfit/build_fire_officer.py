"""Original fictional fire PPE variant; isolated from accepted officer/civilian assets.

Same Scene112 18-bone rig/clips. Visual approximation, no product certification,
brand replication or operational suitability claim. All additions authored here.
"""
from pathlib import Path
import sys
import math
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import assetkit as k
import character_base as c
sys.path.append(str(Path(__file__).resolve().parent.parent / "characters"))
from character_polish import improve

BASE=Path(__file__).resolve().parents[3]
TEX=BASE/'assets/textures/fire_outfit'
OUT=BASE/'assets/models/characters'
c.TEX=TEX
c.OUT=OUT


def strap(root,name,points,width,mat,bone):
    vertices=[(x+side*width*.5,y,z) for x,y,z in points for side in [-1,1]]
    faces=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(points)-1)]
    obj=k.mesh(name,vertices,faces,mat,root)
    thickness=obj.modifiers.new('Woven harness thickness','SOLIDIFY');thickness.thickness=.004;k.apply(obj,thickness)
    c.skin(obj,bone)
    return obj


def band(root,name,z0,z1,cx,cy,rx,ry,mat,bone,count=32):
    # Open cloth strip avoids closed-end subdivision shrinking it inside the coat.
    vertices=[(cx+math.cos(i*math.tau/count)*rx,cy+math.sin(i*math.tau/count)*ry,z)
              for z in [z0,z1] for i in range(count)]
    faces=[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    return c.skin(k.mesh(name,vertices,faces,mat,root),bone)


def sleeve_band(root,name,points,radii,mat,bone):
    from mathutils import Vector
    axis=(Vector(points[-1])-Vector(points[0])).normalized()
    normal=axis.cross(Vector((0,1,0))).normalized()
    other=axis.cross(normal).normalized()
    vertices=[];count=32
    for at,radius in zip(points,radii):
        for i in range(count):
            a=i*math.tau/count
            vertices.append(Vector(at)+normal*math.cos(a)*radius[0]+other*math.sin(a)*radius[1])
    faces=[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    return c.skin(k.mesh(name,vertices,faces,mat,root),bone)


def helmet(root,m):
    shell=k.material('Fictional safety helmet shell',(.44,.40,.15),.37,0.0,TEX)
    dark=m['trim']
    c.ringbody('Original curved helmet',[(1.718,0,-.023,.142,.127),(1.756,0,-.024,.147,.133),
        (1.811,0,-.025,.143,.126),(1.861,0,-.028,.120,.104),(1.902,0,-.028,.067,.065),
        (1.914,0,-.028,.016,.020)],shell,root,'Head')
    brim=k.mesh('Helmet protective brim',[(-.142,.011,1.747),(.142,.011,1.747),(.147,.094,1.739),
        (.117,.159,1.725),(0,.184,1.721),(-.117,.159,1.725),(-.147,.094,1.739)],[(0,1,2,3,4,5,6)],shell,root)
    solid=brim.modifiers.new('Brim rim thickness','SOLIDIFY');solid.thickness=.008;k.apply(brim,solid);c.skin(brim,'Head')
    # Raised original crown ribs and rear impact skirt.
    for x in [-.052,.052]:
        c.tube('Helmet crown rib',[(x,-.108,1.823),(x,-.038,1.908),(x,.072,1.832)],.006,shell,root,'Head')
    skirtverts=[]
    for z,rx,ry in [(1.713,.14,.121),(1.564,.116,.102)]:
        skirtverts += [(math.cos(math.pi+i*math.pi/16)*rx,math.sin(math.pi+i*math.pi/16)*ry-.028,z) for i in range(17)]
    skirt=k.mesh('Rear helmet neck protection',skirtverts,[(i,i+1,i+18,i+17) for i in range(16)],m['top'],root)
    solid=skirt.modifiers.new('Neck protection thickness','SOLIDIFY');solid.thickness=.003;k.apply(skirt,solid);c.skin(skirt,'Head')
    original=k.label('Helmet fictional112','112',(0,.098,1.790),.036,m['badge'],root,(math.pi/2,0,math.pi));c.skin(original,'Head')
    c.tube('Helmet chin strap',[(-.132,.012,1.721),(-.089,.075,1.562),(0,.074,1.529),(.089,.075,1.562),(.132,.012,1.721)],.008,dark,root,'Head')
    # Explicit modeled visor and a fictional face-mask seal/regulator.
    visor=k.material('Clear face visor',(.17,.24,.27),.10,.0,alpha=.18)
    c.sphere('Clear full face mask',(0,.117,1.645),(.102,.033,.101),visor,root,'Head',32,18)
    points=[(.101*math.cos(i*math.tau/48),.117,1.645+.103*math.sin(i*math.tau/48)) for i in range(49)]
    c.tube('Face mask gasket',points,.006,dark,root,'Head')
    c.sphere('Breathing regulator',(0,.151,1.587),(.037,.025,.03),dark,root,'Head')
    c.tube('Regulator supply hose',[(0,.153,1.590),(-.099,.148,1.553),(-.181,.099,1.430),(-.168,.087,1.183),(-.101,-.106,1.128)],.009,dark,root,'Chest')


def equipment(root,m):
    carbon=k.material('SCBA original fibre wrap',(.086,.095,.087),.66,.05,TEX,'fabric')
    accent=m['accent']
    c.box('SCBA rigid backplate',(0,-.123,1.287),(.190,.035,.425),m['trim'],root,'Chest',.025)
    c.ringbody('SCBA rounded air cylinder',[(1.056,0,-.208,.018,.019),(1.071,0,-.208,.052,.054),
        (1.104,0,-.208,.090,.092),(1.460,0,-.208,.090,.092),(1.493,0,-.208,.053,.055),
        (1.506,0,-.208,.018,.019)],carbon,root,'Chest',40)
    for z in [1.146,1.398]:
        band(root,'SCBA securing band',z,z+.024,0,-.208,.094,.096,m['trim'],'Chest')
    band(root,'SCBA fictional identifier',1.24,1.268,0,-.208,.092,.094,accent,'Chest')
    c.box('Cylinder valve',(0,-.207,1.027),(.056,.038,.060),m['metal'],root,'Chest',.010)
    c.sphere('Cylinder handwheel',(.051,-.209,1.025),(.024,.024,.014),m['trim'],root,'Chest')
    for side in [-1,1]:
        strap(root,'SCBA padded shoulder harness',[(side*.097,.118,1.037),(side*.121,.117,1.259),
            (side*.126,.086,1.376),(side*.126,.008,1.443),(side*.097,-.115,1.383),
            (side*.071,-.155,1.229),(side*.064,-.164,1.09)],.032,m['trim'],'Chest')
        c.box('Harness adjuster',(side*.100,.133,1.117),(.040,.013,.026),m['metal'],root,'Chest',.003)
    # Original yellow/silver bands; geometric artwork, not retroreflectivity certification.
    silver=k.material('Fictional silver visibility fabric',(.53,.57,.51),.33,.12,TEX,'fabric')
    for z,rx,ry,bone in [(1.074,.159,.110,'Spine'),(1.123,.161,.113,'Spine')]:
        band(root,'Coat visibility band',z,z+.040,0,-.005,rx,ry,accent,bone)
    band(root,'Coat silver inset',1.085,1.103,0,-.005,.161,.112,silver,'Spine')
    band(root,'Coat second silver inset',1.134,1.151,0,-.005,.163,.115,silver,'Spine')
    for side,tag in [(-1,'L'),(1,'R')]:
        x=side*.105
        band(root,'Trouser visibility band'+tag,.266,.319,x,-.010,.066,.072,accent,tag+'Shin')
        band(root,'Trouser silver inset'+tag,.283,.301,x,-.010,.068,.074,silver,tag+'Shin')
        sleeve_band(root,'Sleeve visibility band'+tag,[(side*.374,.022,1.072),(side*.386,.029,1.018)],[(.052,.053),(.047,.049)],accent,tag+'ForeArm')
        sleeve_band(root,'Sleeve silver inset'+tag,[(side*.377,.024,1.061),(side*.382,.027,1.039)],[(.054,.055),(.052,.052)],silver,tag+'ForeArm')
        c.box('Coat reinforced pocket',(side*.117,.102,1.017),(.075,.021,.09),m['top'],root,'Spine',.01)


def build():
    k.clean();c.PARTS.clear()
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    root=k.empty('FireOfficerAvatar')
    m=c.materials(True)
    m['top']=k.material('Original tan bunker coat',(.30,.245,.141),.91,0,TEX,'fabric')
    m['pants']=k.material('Original tan bunker trousers',(.255,.203,.110),.91,0,TEX,'fabric')
    m['accent']=k.material('Fictional yellow visibility fabric',(.48,.48,.145),.43,0,TEX,'fabric')
    glove=k.material('Fire protective glove cloth',(.173,.153,.109),.91,0,TEX,'fabric')
    skin=m['skin'];m['skin']=glove
    c.body(root,m,True)
    m['skin']=skin
    for obj in c.PARTS:
        if obj.name.startswith('Fingernail'):obj.data.materials.clear();obj.data.materials.append(glove)
        if any(tag in obj.name for tag in ['TailoredUniform','TailoredSleeve','FittedTrouserLeg']):
            cx=sum(v.co.x for v in obj.data.vertices)/len(obj.data.vertices)
            cy=sum(v.co.y for v in obj.data.vertices)/len(obj.data.vertices)
            for v in obj.data.vertices:
                v.co.x=cx+(v.co.x-cx)*1.06
                v.co.y=cy+(v.co.y-cy)*1.08
    c.face(root,m,False)
    helmet(root,m);equipment(root,m)
    improve(c,root,m,True,ppe=True)
    arm=c.rig(root);c.animate(arm)
    k.finish(root,OUT,'fire_officer',3.8,1.92)


build()
