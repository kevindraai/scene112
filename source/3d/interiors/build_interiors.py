"""Original compact SCENE112 training furniture, four consolidated prop meshes.

Render decor only; gameplay IDs, collision and interactions belong to the game.
Metric +Y front Blender -> Godot -Z front, +Y up. No third-party assets.
"""
from pathlib import Path
import sys
import math
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import assetkit as k

BASE=Path(__file__).resolve().parents[3]
TEX=BASE/'assets/textures/interiors'
OUT=BASE/'assets/models/interiors'


def consolidate(root,name):
    meshes=[o for o in root.children_recursive if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name+'Surface'
    k.parent(obj,root)
    obj.select_set(False)
    return obj


def locker(root,m):
    prop=k.empty('TrainingLocker');k.parent(prop,root)
    # Two bays, one closed and one visibly equipped; real seams/hinges/vents.
    for x in [-.61,.61]:k.box('LockerSide',(x,0,1.105),(.035,.64,2.12),m['powder'],prop,.010)
    k.box('LockerBack',(0,-.305,1.105),(1.22,.027,2.12),m['powder'],prop,.007)
    for z in [.06,2.15]:k.box('LockerTopBottom',(0,0,z),(1.25,.66,.045),m['powder'],prop,.012)
    k.box('LockerDivider',(0,0,1.105),(.025,.60,2.08),m['steel'],prop,.007)
    for x in [-.315,.315]:
        k.box('LockerShelf',(x,0,1.755),(.57,.58,.018),m['steel'],prop,.005)
        k.box('BootShelf',(x,0,.245),(.57,.58,.025),m['steel'],prop,.007)
        for z in [.55,1.45,1.91]:k.box('LockerHinge',(x+(.28 if x>0 else -.28),.32,z),(.032,.037,.08),m['steel'],prop,.004)
    k.box('ClosedLockerDoor',(-.307,.330,1.102),(.566,.023,2.034),m['powder'],prop,.010)
    k.box('RecessedDoorGrip',(-.084,.348,1.143),(.027,.015,.19),m['steel'],prop,.009)
    for z in [1.57,1.63,1.69,1.89,1.95]:k.box('VentSlot',(-.311,.345,z),(.34,.006,.014),m['fabric'],prop,.004)
    k.label('LockerNumber','01',(-.30,.349,1.777),.070,m['steel'],prop,(math.pi/2,0,math.pi))
    door=k.empty('OpenLockerDoor',(.60,.33,0));k.parent(door,prop)
    k.box('OpenDoorLeaf',(.31,.33,1.102),(.566,.023,2.034),m['powder'],door,.010)
    k.box('OpenDoorHandle',(.080,.349,1.143),(.030,.024,.18),m['steel'],door,.009)
    for z in [1.57,1.63,1.69,1.89,1.95]:k.box('OpenDoorVent',(.31,.345,z),(.34,.006,.014),m['fabric'],door,.004)
    door.rotation_euler.z=math.radians(-53)
    bpy.context.view_layer.update()
    # An authored coat form hangs from a triangular hanger inside the open bay.
    k.tube('Hanger',[(.315,-.02,1.655),(.115,-.02,1.50),(.515,-.02,1.50),(.315,-.02,1.655)],.009,m['steel'],prop)
    k.tube('HangerHook',[(.315,-.02,1.655),(.315,-.02,1.70),(.349,-.02,1.72),(.375,-.02,1.70)],.008,m['steel'],prop)
    k.box('StoredCoatTorso',(.315,-.014,1.190),(.32,.11,.62),m['fabric'],prop,.05)
    for side in [-1,1]:
        sleeve=k.box('StoredCoatSleeve',(.315+side*.178,-.002,1.26),(.12,.11,.47),m['fabric'],prop,.04)
        sleeve.rotation_euler.y=side*.13
    k.box('CoatZip',(.315,.045,1.25),(.011,.007,.45),m['steel'],prop,.002)
    for x in [.23,.39]:k.sphere('StoredBoot',(x,.015,.365),(.070,.18,.10),m['fabric'],prop,24,14)
    k.sphere('StoredHelmet',(.315,.035,1.855),(.17,.145,.092),m['steel'],prop,28,16)
    for x in [-.48,.48]:
        for y in [-.24,.24]:k.box('LockerFoot',(x,y,.032),(.06,.06,.064),m['fabric'],prop,.007)
    consolidate(prop,'TrainingLocker')
    prop.location.x=-3.5
    return prop


def desk(root,m):
    prop=k.empty('RadioDesk');k.parent(prop,root)
    k.box('LaminatedDeskTop',(0,0,.778),(1.80,.85,.043),m['oak'],prop,.017)
    for x in [-.81,.81]:
        for y in [-.32,.32]:k.box('DeskSquareLeg',(x,y,.382),(.045,.045,.74),m['steel'],prop,.006)
    k.box('DeskRearBrace',(0,-.32,.36),(1.64,.027,.033),m['steel'],prop,.004)
    k.box('DeskModestyPanel',(0,-.29,.554),(1.55,.035,.285),m['powder'],prop,.010)
    k.box('DrawerPedestal',(-.53,-.045,.532),(.46,.58,.435),m['powder'],prop,.012)
    for z in [.438,.567,.698]:
        k.box('DrawerFront',(-.53,.261,z),(.42,.024,.112),m['powder'],prop,.005)
        k.box('DrawerPull',(-.53,.285,z+.016),(.20,.032,.021),m['steel'],prop,.007)
    # Fictive console: dial, button rows, angled screen, handset and coiled cord.
    radio=k.box('RadioConsole',(0.27,-.055,.905),(.65,.39,.20),m['powder'],prop,.025)
    face=k.box('RadioFrontPanel',(.27,.149,.922),(.604,.015,.165),m['fabric'],prop,.011)
    k.box('RadioDisplay',(.16,.161,.941),(.28,.005,.089),m['fabric'],prop,.005)
    k.label('RadioReadout','112  RADIO',(.16,.166,.927),.032,m['steel'],prop,(math.pi/2,0,math.pi))
    for x in [.38,.52]:
        k.cylinder('RotaryRadioKnob',(x,.17,.929),.029,.042,m['fabric'],prop,(0,1,0),24)
        k.cylinder('KnobCentre',(x,.193,.929),.010,.009,m['steel'],prop,(0,1,0),20)
    for x in [.07,.14,.21,.28]:k.box('RadioButton',(x,.171,.869),(.041,.022,.023),m['steel'],prop,.004)
    k.tube('ConsoleAntenna',[(.50,-.175,1.011),(.50,-.175,1.251)],.008,m['powder'],prop)
    k.box('HandsetCradle',(-.245,-.048,.827),(.20,.39,.05),m['powder'],prop,.014)
    k.tube('HandsetGrip',[(-.25,-.194,.872),(-.25,.096,.872)],.033,m['fabric'],prop)
    for y in [-.191,.098]:k.box('HandsetEnd',(-.25,y,.88),(.112,.097,.063),m['fabric'],prop,.029)
    cord=[(-.14+.005*i,.10+math.sin(i*math.tau/8)*.016,.848+math.cos(i*math.tau/8)*.016) for i in range(64)]
    k.tube('CoiledHandsetCord',cord,.0038,m['fabric'],prop)
    k.box('DocumentFolder',(-.57,.08,.81),(.30,.32,.012),m['oak'],prop,.004)
    k.tube('DeskPen',[(-.46,.155,.824),(-.46,.304,.824)],.004,m['powder'],prop)
    consolidate(prop,'RadioDesk')
    prop.location.x=-1.1
    return prop


def chair(root,m):
    prop=k.empty('BureauChair');k.parent(prop,root)
    for i in range(5):
        angle=i*math.tau/5
        x,y=math.cos(angle)*.31,math.sin(angle)*.31
        k.tube('FiveStarBaseArm',[(0,0,.14),(x*.72,y*.72,.103),(x,y,.078)],.024,m['powder'],prop)
        k.cylinder('CasterWheel',(x,y,.043),.043,.06,m['fabric'],prop,(-math.sin(angle),math.cos(angle),0),24)
    k.cylinder('GasLift',(0,0,.30),.035,.34,m['steel'],prop)
    k.cylinder('LiftCover',(0,0,.245),.05,.16,m['powder'],prop)
    k.box('ChairSeatShell',(0,0,.477),(.49,.47,.04),m['powder'],prop,.022)
    k.box('UpholsteredSeat',(0,.011,.523),(.47,.45,.068),m['fabric'],prop,.04)
    k.tube('BackrestSupport',[(0,-.155,.472),(0,-.241,.64),(0,-.28,.88)],.022,m['steel'],prop)
    back=k.box('ContouredBackrest',(0,-.226,.793),(.452,.078,.43),m['fabric'],prop,.045)
    back.rotation_euler.x=math.radians(-10)
    for side in [-1,1]:
        k.tube('ArmrestSupport',[(side*.197,-.12,.486),(side*.26,-.10,.68),(side*.26,.11,.70)],.014,m['powder'],prop)
        k.box('PaddedArmrest',(side*.26,.006,.715),(.067,.27,.040),m['fabric'],prop,.018)
    k.tube('SeatAdjuster',[(.22,.035,.451),(.31,.035,.44)],.008,m['steel'],prop)
    k.box('AdjusterGrip',(.315,.035,.44),(.046,.05,.02),m['fabric'],prop,.009)
    consolidate(prop,'BureauChair')
    prop.location.x=1.1
    return prop


def evidence(root,m):
    prop=k.empty('EvidenceBench');k.parent(prop,root)
    k.box('EvidenceWorkTop',(0,0,.918),(1.58,.74,.04),m['oak'],prop,.015)
    for x in [-.69,.69]:
        for y in [-.27,.27]:k.box('BenchFrameLeg',(x,y,.45),(.05,.05,.87),m['steel'],prop,.007)
    k.box('BenchLowerShelf',(0,0,.24),(1.44,.60,.026),m['powder'],prop,.008)
    k.box('BenchBackRail',(0,-.31,.826),(1.46,.025,.10),m['steel'],prop,.004)
    k.box('HandlingMat',(-.15,.02,.943),(.64,.50,.009),m['fabric'],prop,.012)
    k.box('FictiveCapturePad',(-.15,.025,.978),(.32,.26,.060),m['powder'],prop,.015)
    k.box('CapturePlate',(-.15,.04,1.011),(.24,.19,.009),m['steel'],prop,.01)
    k.label('PadIdentifier','112',(-.15,.153,1.018),.035,m['powder'],prop,(0,0,math.pi))
    k.box('ScannerCableConnector',(-.015,-.105,.988),(.029,.032,.020),m['fabric'],prop,.005)
    k.tube('ScannerCable',[(-.015,-.105,.985),(.029,-.222,.976),(.19,-.245,.955),(.29,-.22,.943)],.004,m['fabric'],prop)
    for x in [.43,.63]:
        k.box('SealedStorageBin',(x,-.13,1.02),(.17,.33,.17),m['powder'],prop,.009)
        k.box('StorageBinLid',(x,-.13,1.111),(.178,.34,.020),m['steel'],prop,.006)
        k.box('BinPull',(x,.047,1.047),(.073,.013,.02),m['steel'],prop,.006)
    k.box('FlatCaseTray',(.45,.171,.954),(.39,.22,.02),m['powder'],prop,.009)
    for x in [-.39,.20,.47]:
        k.box('UnderBenchCase',(x,-.026,.363),(.32,.44,.205),m['powder'],prop,.014)
        k.box('CaseHandle',(x,.206,.378),(.14,.025,.025),m['steel'],prop,.007)
    # Original articulated-looking desk light, decoration only (no light node).
    k.cylinder('TaskLightBase',(-.61,-.23,.958),.09,.032,m['steel'],prop)
    k.tube('TaskLightArm',[(-.61,-.23,.97),(-.64,-.23,1.28),(-.45,-.10,1.40)],.012,m['steel'],prop)
    k.sphere('TaskLightShade',(-.42,-.08,1.401),(.107,.070,.039),m['powder'],prop,24,14)
    k.box('TaskLightDiffuser',(-.42,-.08,1.369),(.14,.09,.009),m['steel'],prop,.012)
    consolidate(prop,'EvidenceBench')
    prop.location.x=3.3
    return prop


def build():
    k.clean()
    root=k.empty('TrainingInteriorSet')
    m={'powder':k.material('Interior original powder coating',(.025,.06,.08),.54,.18,TEX),
       'steel':k.material('Interior brushed steel',(.40,.43,.44),.36,.85,TEX),
       'oak':k.material('Interior laminated oak',(.34,.22,.115),.60,0,TEX,'wood'),
       'fabric':k.material('Interior upholstery and polymer',(.025,.03,.03),.85,0,TEX,'fabric')}
    locker(root,m);desk(root,m);chair(root,m);evidence(root,m)
    k.finish(root,OUT,'training_interiors',9.5,2.2)


build()
