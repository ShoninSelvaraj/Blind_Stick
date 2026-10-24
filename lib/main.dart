import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 await Firebase.initializeApp();
 final preferences = await SharedPreferences.getInstance();
 voiceGuidanceEnabled = preferences.getBool('voice') ?? true;
 appTextScale.value = preferences.getDouble('text_scale') ?? 1.0;
 appHighContrast.value = preferences.getBool('high_contrast') ?? false;
 runApp(const BlindStickApp());
}

const navy = Color(0xFF17233B);
const teal = Color(0xFF007F78);
const pale = Color(0xFFEAF7F4);
const red = Color(0xFFB42318);
const serviceUuid = '7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001';
const telemetryUuid = '7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001';
const commandUuid = '7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001';
const defaultMapTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const defaultGeocoderBaseUrl = 'https://nominatim.openstreetmap.org';
const defaultFootRouterBaseUrl = 'https://routing.openstreetmap.de/routed-foot/route/v1/driving';
bool voiceGuidanceEnabled = true;
final ValueNotifier<double> appTextScale = ValueNotifier<double>(1.0);
final ValueNotifier<bool> appHighContrast = ValueNotifier<bool>(false);

class BlindStickApp extends StatelessWidget {
  const BlindStickApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: appHighContrast,
    builder: (context, highContrast, _) => MaterialApp(
      title: 'BlindStick Companion', debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: highContrast
            ? const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, secondary: Colors.black, onSecondary: Colors.white, surface: Colors.white, onSurface: Colors.black)
            : ColorScheme.fromSeed(seedColor: teal),
        scaffoldBackgroundColor: highContrast ? Colors.white : const Color(0xFFF7FAFC),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      home: const AuthGate(),
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: appTextScale,
        builder: (context, scale, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1.0) * scale)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

enum Role { patient, caregiver }
class AppUser { final String uid, username, name; final Role role; const AppUser({required this.uid, required this.username, required this.name, required this.role}); }
class AuthGate extends StatelessWidget {
 const AuthGate({super.key});
 @override Widget build(BuildContext context) => StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(),builder:(context,auth){
  if(auth.connectionState==ConnectionState.waiting)return const Scaffold(body:Center(child:CircularProgressIndicator()));
  final user=auth.data;if(user==null)return const LoginPage();
  return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),builder:(context,profile){
   if(profile.connectionState==ConnectionState.waiting)return const Scaffold(body:Center(child:CircularProgressIndicator()));
   final data=profile.data?.data();final role=data?['role'];
   if(data==null||(role!='patient'&&role!='caregiver'))return ProfilePendingPage(email:user.email??'');
   final appUser=AppUser(uid:user.uid,username:user.email??user.uid,name:(data['displayName']??user.displayName??'Friend').toString(),role:role=='patient'?Role.patient:Role.caregiver);
   return role=='patient'?PatientPage(user:appUser):CaregiverPage(user:appUser);
  });
 });
}
class ProfilePendingPage extends StatelessWidget {
 final String email;const ProfilePendingPage({super.key,required this.email});
 @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
 const Icon(Icons.verified_user_outlined,size:64,color:teal),const SizedBox(height:18),const Text('Account created',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:12),
 Text('Signed in as $email. Your account profile is not ready. Sign out and try again, or contact support if this continues.',textAlign:TextAlign.center,style:const TextStyle(fontSize:16)),const SizedBox(height:22),FilledButton.icon(onPressed:signOutSafely,icon:const Icon(Icons.logout),label:const Text('Sign out'))
 ])))));
}

class LoginPage extends StatefulWidget { const LoginPage({super.key}); @override State<LoginPage> createState()=>_LoginPageState(); }
class _LoginPageState extends State<LoginPage> {
 final email=TextEditingController(),password=TextEditingController(),name=TextEditingController();bool hide=true,createAccount=false,busy=false;Role selectedRole=Role.patient;String? error,info;
 @override void dispose(){email.dispose();password.dispose();name.dispose();super.dispose();}
 Future<void> submit() async {
  if(busy)return;
  if(email.text.trim().isEmpty||!email.text.contains('@')||password.text.length<6||(createAccount&&name.text.trim().isEmpty)){setState(()=>error=createAccount?'Enter your name, a valid email and a password of at least 6 characters.':'Enter your email and password (at least 6 characters).');return;}
  setState(() { busy=true; error=null; info=null; });
  try{
   if(createAccount){
    final credential=await FirebaseAuth.instance.createUserWithEmailAndPassword(email:email.text.trim(),password:password.text);
    await credential.user!.updateDisplayName(name.text.trim());
    await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({'uid':credential.user!.uid,'email':email.text.trim().toLowerCase(),'displayName':name.text.trim(),'role':selectedRole==Role.patient?'patient':'caregiver','createdAt':FieldValue.serverTimestamp()});
    if(mounted)setState(()=>info=selectedRole==Role.patient?'Account ready. Connect your stick from the patient screen.':'Account ready. To view a patient, you still need to be paired with them.');
   }else{await FirebaseAuth.instance.signInWithEmailAndPassword(email:email.text.trim(),password:password.text);}
  }on FirebaseAuthException catch(ex){
   if(mounted) { setState(()=>error=switch(ex.code){
    'invalid-email'=>'That email address is not valid.','user-not-found'=>'No account exists for this email. Choose Create account first.',
    'wrong-password'||'invalid-credential'=>'Email or password is incorrect.','email-already-in-use'=>'An account already exists for this email. Sign in instead.',
    'weak-password'=>'Choose a stronger password.','network-request-failed'=>'No network connection. Check internet and try again.',
    'too-many-requests'=>'Too many attempts. Wait a little before trying again.',_=>'Could not authenticate (${ex.code}). Check Firebase Authentication settings.'}); }
  }catch(ex){if(mounted)setState(()=>error='Could not finish sign-in. Check Firebase configuration and Firestore rules.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> resetPassword()async{
  if(email.text.trim().isEmpty){setState(()=>error='Enter your email first, then tap Forgot password.');return;}
  try{await FirebaseAuth.instance.sendPasswordResetEmail(email:email.text.trim());if(mounted)setState(()=>info='Password reset email requested. Check your inbox and spam folder.');}
  on FirebaseAuthException catch(ex){if(mounted)setState(()=>error='Could not send reset email (${ex.code}).');}
 }
 Widget _roleChoice(Role role,String title,String detail,IconData icon) {
  final selected = selectedRole == role;
  return Semantics(
   container:true, button:true, selected:selected,
   label:'$title. $detail',
   child: Material(
    color:selected?pale:Colors.white,
    borderRadius:BorderRadius.circular(18),
    child: InkWell(
     borderRadius:BorderRadius.circular(18),
     onTap:()=>setState(()=>selectedRole=role),
     child: Container(
      padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(
       borderRadius:BorderRadius.circular(18),
       border:Border.all(color:selected?teal:const Color(0xFFDCE5E9),width:selected?2:1),
      ),
      child:Row(children:[
       Icon(icon,size:32,color:selected?teal:navy),
       const SizedBox(width:14),
       Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:navy)),
        const SizedBox(height:4),
        Text(detail,style:const TextStyle(fontSize:14,color:Color(0xFF59697B))),
       ])),
       const SizedBox(width:10),
       Icon(selected?Icons.check_circle:Icons.circle_outlined,color:selected?teal:const Color(0xFF91A0AE),size:26),
      ]),
     ),
    ),
   ),
  );
 }
 @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
 const SizedBox(height:16),Container(width:68,height:68,alignment:Alignment.center,decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(22)),child:const Icon(Icons.accessibility_new_rounded,color:Colors.white,size:42)),
 const SizedBox(height:20),const Text('BlindStick Companion',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,color:navy)),const Text('Your companion for safer journeys',style:TextStyle(fontSize:17,color:Color(0xFF59697B))),const SizedBox(height:32),
 Text(createAccount?'Create your account':'Welcome back',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:16),
 if(createAccount)...[
  const Text('Choose how you’d like to use this app',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:navy)),
  const SizedBox(height:12),
  _roleChoice(Role.patient,'Use my smart stick','Navigate, hear safety alerts and ask for help.',Icons.accessibility_new_rounded),
  const SizedBox(height:10),
  _roleChoice(Role.caregiver,'Support someone I care about','Stay connected when they choose to share updates.',Icons.people_alt_outlined),
  const SizedBox(height:14),
 ],
 if(createAccount)...[TextField(controller:name,textCapitalization:TextCapitalization.words,autofillHints:const [AutofillHints.name],decoration:const InputDecoration(labelText:'Your name',prefixIcon:Icon(Icons.person_outline))),const SizedBox(height:12)],
 TextField(controller:email,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],textInputAction:TextInputAction.next,decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.email_outlined))),const SizedBox(height:12),
 TextField(controller:password,obscureText:hide,autofillHints:createAccount?const [AutofillHints.newPassword]:const [AutofillHints.password],onSubmitted:(_)=>submit(),decoration:InputDecoration(labelText:'Password',helperText:createAccount?'Use at least 6 characters':'',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>hide=!hide),icon:Icon(hide?Icons.visibility:Icons.visibility_off)))),
 if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:red))),if(info!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(info!,style:const TextStyle(color:teal))),
 const SizedBox(height:20),SizedBox(height:58,child:FilledButton.icon(onPressed:busy?null:submit,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Icon(createAccount?Icons.person_add_alt_1:Icons.arrow_forward),label:Text(busy?'Please wait…':createAccount?'Create account':'Sign in',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))),
 if(!createAccount)Align(alignment:Alignment.centerRight,child:TextButton(onPressed:busy?null:resetPassword,child:const Text('Forgot password?'))),
 TextButton(onPressed:busy?null:()=>setState(() { createAccount=!createAccount; error=null; info=null; }),child:Text(createAccount?'Already have an account? Sign in':'New here? Create an account')),
 const SizedBox(height:20),const Text('You can change your choice on a new account only. Caregiver access to someone’s location always requires a private, one-time pairing code from that person.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF64748B),fontSize:13))
 ])));
}
class StickTelemetry {
 double? distanceCm; String object='Waiting for device data'; String signal='unknown'; int? battery; bool? trafficWalk; String crowd='unknown'; String detectionStatus='waiting_for_device'; bool? cameraReady; bool? cameraFrameAvailable; DateTime? receivedAt;
 bool get urgent=>distanceCm!=null&&distanceCm!<35;
 bool get caution=>distanceCm!=null&&distanceCm!<90;
 void fromJson(Map<String,dynamic> j){
  final d=j['distance_cm']??j['distanceCm']??j['distance']; if(d is num)distanceCm=d.toDouble();
  object=(j['object']??j['detected_object']??j['label']??object).toString(); signal=(j['signal']??signal).toString();
  final b=j['battery']??j['battery_percent']; if(b is num)battery=b.toInt();
  if(j['traffic_walk'] is bool)trafficWalk=j['traffic_walk'];
  if(j['crowd']!=null)crowd=j['crowd'].toString();
  if(j['detection_status']!=null)detectionStatus=j['detection_status'].toString();
  if(j['camera_ready'] is bool)cameraReady=j['camera_ready'];
  if(j['camera_frame_available'] is bool)cameraFrameAvailable=j['camera_frame_available'];
  receivedAt=DateTime.now();
 }
}

class ApiService {
 static final ApiService instance=ApiService._();
 ApiService._();
 final FirebaseFirestore db=FirebaseFirestore.instance;
 Future<bool> sos(String patientUid,Position? pos,String detail) async {
  try {
   await db.collection('patients').doc(patientUid).collection('alerts').add({
    'type':'sos','message':detail,'createdAt':FieldValue.serverTimestamp(),
    if(pos!=null)'latitude':pos.latitude,
    if(pos!=null)'longitude':pos.longitude,
    'deliveryStatus':'saved',
   });
   return true;
  } catch (_) { return false; }
 }
 Future<bool> location(String patientUid,Position pos) async {
  try {
   final ref=db.collection('patients').doc(patientUid);
   final loc={'latitude':pos.latitude,'longitude':pos.longitude,'accuracyM':pos.accuracy,'recordedAt':FieldValue.serverTimestamp()};
   await ref.collection('locations').add(loc);
   await ref.update({'lastLocation':loc,'lastSeenAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
   return true;
  } catch (_) { return false; }
 }
 Future<bool> event(String patientUid,String kind,String detail) async {
  try {
   await db.collection('patients').doc(patientUid).collection('alerts').add({
    'type':kind,'message':detail,'createdAt':FieldValue.serverTimestamp(),'deliveryStatus':'saved',
   });
   return true;
  } catch (_) { return false; }
 }
}

Future<void> signOutSafely() async {
 if(stick.connected){
  try{await stick.setAssistance(false);await stick.disconnect();}catch(_){}
 }
 await FirebaseAuth.instance.signOut();
}

Future<void> confirmSignOut(BuildContext context) async {
 final confirm=await showDialog<bool>(
  context:context,
  builder:(dialogContext)=>AlertDialog(
   title:const Text('Sign out?'),
   content:const Text('You can sign in again with your email and password.'),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
    FilledButton.icon(onPressed:()=>Navigator.pop(dialogContext,true),icon:const Icon(Icons.logout),label:const Text('Sign out')),
   ],
  ),
 );
 if(confirm==true)await signOutSafely();
}

class PairingService {
 static final FirebaseFirestore _db=FirebaseFirestore.instance;
 static final math.Random _random=math.Random.secure();

 static Future<(String,DateTime)> createCode(String patientUid) async {
  for(var attempt=0;attempt<6;attempt++){
   final code=List.generate(8,(_)=>_random.nextInt(10)).join();
   final ref=_db.collection('pairingCodes').doc(code);
   final expires=DateTime.now().add(const Duration(minutes:10));
   final created=await _db.runTransaction<bool>((tx)async{
    final existing=await tx.get(ref);
    if(existing.exists)return false;
    tx.set(ref,{
     'patientUid':patientUid,
     'createdAt':FieldValue.serverTimestamp(),
     'expiresAt':Timestamp.fromDate(expires),
     'usedBy':null,
     'usedAt':null,
    });
    return true;
   });
   if(created)return (code,expires);
  }
  throw StateError('Could not create a pairing code. Please try again.');
 }

 static Future<void> redeemCode(String code,String caregiverUid) async {
  if(!RegExp(r'^\d{8}$').hasMatch(code))throw StateError('Enter the full 8-digit code.');
  final codeRef=_db.collection('pairingCodes').doc(code);
  final claimRef=_db.collection('pairingClaims').doc(caregiverUid);
  await _db.runTransaction<void>((tx)async{
   final codeSnap=await tx.get(codeRef);
   final claimSnap=await tx.get(claimRef);
   if(!codeSnap.exists)throw StateError('That code is invalid or has expired. Ask them to create a new one.');
   if(claimSnap.exists)throw StateError('This account is already linked. Ask support to change an existing pairing.');
   final codeData=codeSnap.data()!;
   final expires=codeData['expiresAt'];
   if(codeData['usedBy']!=null || expires is! Timestamp || !expires.toDate().isAfter(DateTime.now())){
    throw StateError('That code has expired or has already been used. Ask them to create a new one.');
   }
   final patientUid=(codeData['patientUid']??'').toString();
   if(patientUid.isEmpty||patientUid==caregiverUid)throw StateError('This code cannot be used for this account.');
   final patientRef=_db.collection('patients').doc(patientUid);
   tx.set(claimRef,{
    'patientUid':patientUid,
    'caregiverUid':caregiverUid,
    'code':code,
    'createdAt':FieldValue.serverTimestamp(),
   });
   tx.update(codeRef,{'usedBy':caregiverUid,'usedAt':FieldValue.serverTimestamp()});
   tx.update(patientRef,{'caregiverUids':FieldValue.arrayUnion([caregiverUid])});
  });
 }
}

class BleStickService extends ChangeNotifier {
 final FlutterTts tts=FlutterTts(); final StickTelemetry telemetry=StickTelemetry(); BluetoothDevice? device; BluetoothCharacteristic? telemetryChar, commandChar; StreamSubscription<List<int>>? notifySub; StreamSubscription<BluetoothConnectionState>? connectionSub;
 bool scanning=false,connected=false,assistance=false; String status='Stick not connected'; String? lastError; final List<String> events=[]; String _lastWarning=''; String _packetBuffer='';Timer? _freshnessTimer;bool _staleWarningSpoken=false;
 BleStickService(){tts.setLanguage('en-IN');tts.setSpeechRate(0.46);_freshnessTimer=Timer.periodic(const Duration(seconds:1),(_){if(!connected||!assistance)return;final last=telemetry.receivedAt;final stale=last==null||DateTime.now().difference(last)>const Duration(seconds:4);if(stale&&!_staleWarningSpoken){_staleWarningSpoken=true;lastError='Live stick data stopped. Do not rely on the app for obstacle warnings.';_event('Live sensor data stopped');HapticFeedback.heavyImpact();_speak('Warning. Live stick data has stopped. Stop and use your usual safe mobility method.');notifyListeners();}else if(!stale&&_staleWarningSpoken){_staleWarningSpoken=false;lastError=null;notifyListeners();}});}
 Future<void> scanAndConnect() async {
  if(scanning)return;
  if(connected)await disconnect();
  scanning=true;status='Looking for your stick';lastError=null;notifyListeners();
  try{
   final scanPermission=await Permission.bluetoothScan.request();
   final connectPermission=await Permission.bluetoothConnect.request();
   if(!scanPermission.isGranted||!connectPermission.isGranted){status='Bluetooth permission needed';lastError='Allow Bluetooth access in Android settings to find the stick.';return;}
   final state=await FlutterBluePlus.adapterState.first; if(state!=BluetoothAdapterState.on){status='Please turn Bluetooth on';lastError='Bluetooth is off';scanning=false;notifyListeners();return;}
   await FlutterBluePlus.startScan(timeout:const Duration(seconds:12),withServices:[Guid(serviceUuid)]);
   final results=await FlutterBluePlus.scanResults.firstWhere((r)=>r.any((x)=>x.advertisementData.serviceUuids.any((g)=>g==Guid(serviceUuid)))).timeout(const Duration(seconds:12),onTimeout:()=> <ScanResult>[]);
   final match=results.where((x)=>x.advertisementData.serviceUuids.any((g)=>g==Guid(serviceUuid))).toList();
   if(match.isEmpty){status='Stick not found';lastError='No device advertising the BlindStick Companion service was found. Check that the stick is powered on and running the matching firmware.';return;}
   device=match.first.device; await device!.connect(timeout:const Duration(seconds:15));
   connectionSub?.cancel();connectionSub=device!.connectionState.listen((s){connected=s==BluetoothConnectionState.connected;if(!connected){assistance=false;status='Connection lost — stick alerts may be unavailable';_event('Connection lost');}else{status='Stick connected';_event('Stick connected');}notifyListeners();});
   final services=await device!.discoverServices(); BluetoothService? svc;
   for(final s in services){if(s.serviceUuid==Guid(serviceUuid)){svc=s;break;}}
   if(svc==null)throw Exception('Firmware service UUID does not match the app.');
   for(final ch in svc.characteristics){if(ch.characteristicUuid==Guid(telemetryUuid))telemetryChar=ch;if(ch.characteristicUuid==Guid(commandUuid))commandChar=ch;}
   if(telemetryChar==null)throw Exception('Telemetry characteristic is missing.');
   if(commandChar==null)throw Exception('Command characteristic is missing.');
   await telemetryChar!.setNotifyValue(true); notifySub?.cancel();notifySub=telemetryChar!.onValueReceived.listen(_handlePacket);
   status='Stick connected';lastError=null;await _command({'cmd':'hello','protocol':1});
  }catch(e){await device?.disconnect();status='Could not connect';lastError=e.toString().replaceFirst('Exception: ','');connected=false;}
  finally{await FlutterBluePlus.stopScan();scanning=false;notifyListeners();}
 }
 void _handlePacket(List<int> bytes){
  _packetBuffer += utf8.decode(bytes,allowMalformed:true);
  while(_packetBuffer.contains('\n')){
   final index=_packetBuffer.indexOf('\n');
   final line=_packetBuffer.substring(0,index).trim();
   _packetBuffer=_packetBuffer.substring(index+1);
   if(line.isEmpty)continue;
   try{
    final decoded=jsonDecode(line);
    if(decoded is Map<String,dynamic>){telemetry.fromJson(decoded);_processSafety();}
   }catch(_){lastError='Unreadable data received from stick. Check the firmware packet format.';}
  }
  notifyListeners();
 }
 void _processSafety(){
  final t=telemetry;
  // Keep warnings priority-ordered: close obstacle must never be overwritten by a less urgent cue.
  String warning='';
  if(t.distanceCm!=null&&t.distanceCm!<35){warning='Stop. Obstacle very close.';}
  else if(t.trafficWalk==false&&t.object.toLowerCase().contains('traffic')){warning='Stop. Do not cross yet. Check the crossing yourself.';}
  else if(t.distanceCm!=null&&t.distanceCm!<90){warning='Caution. Obstacle ahead.';}
  else if(t.crowd.toLowerCase()=='high'){warning='Crowded area ahead. Slow down.';}
  if(warning.isNotEmpty&&warning!=_lastWarning){
   _lastWarning=warning;_event(warning);HapticFeedback.heavyImpact();_speak(warning);
  }
  if(warning.isEmpty)_lastWarning='';
 }
 Future<void> _command(Map<String,dynamic> cmd)async{if(!connected||commandChar==null)return;final bytes=utf8.encode('${jsonEncode(cmd)}\n');await commandChar!.write(bytes,withoutResponse:commandChar!.properties.writeWithoutResponse&&!commandChar!.properties.write);}
 Future<void> setAssistance(bool on)async{assistance=on;await _command({'cmd':on?'start':'stop'});_event(on?'Assistance started':'Assistance paused');if(on)_speak('Assistance started. Stay aware of your surroundings.');notifyListeners();}
 Future<void> _speak(String s)async{if(!voiceGuidanceEnabled)return;await tts.stop();await tts.speak(s);}
 Future<void> announce(String s)=>_speak(s);
 void _event(String s){final now=DateTime.now();final stamp='${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';events.insert(0,'$stamp · $s');if(events.length>50)events.removeLast();final user=FirebaseAuth.instance.currentUser;if(user!=null){ApiService.instance.event(user.uid,'system',s);}}
 Future<void> disconnect()async{await device?.disconnect();connected=false;assistance=false;status='Stick disconnected';notifyListeners();}
 @override void dispose(){notifySub?.cancel();connectionSub?.cancel();device?.disconnect();tts.stop();_freshnessTimer?.cancel();super.dispose();}
}
final stick=BleStickService();

Future<Position?> getPosition()async{try{if(!await Geolocator.isLocationServiceEnabled())return null;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)return null;return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:15)));}catch(_){return null;}}

Future<void> openNavigation(BuildContext context, String destination) async {
  final place = destination.trim();
  if (place.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter a destination first.')),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => InAppNavigationPage(initialQuery: place),
    ),
  );
}

class NavigationStep {
  final String instruction;
  final LatLng location;
  final double distanceMeters;
  const NavigationStep({
    required this.instruction,
    required this.location,
    required this.distanceMeters,
  });
}

/// In-app map using OpenStreetMap data and public community geocoding/routing endpoints.
/// Public services are best-effort prototypes and do not provide an availability guarantee.
class InAppNavigationPage extends StatefulWidget {
  final String? initialQuery;
  final LatLng? initialDestination;
  final String initialDestinationLabel;
  const InAppNavigationPage({
    super.key,
    this.initialQuery,
    this.initialDestination,
    this.initialDestinationLabel = 'Shared location',
  });

  @override
  State<InAppNavigationPage> createState() => _InAppNavigationPageState();
}

class _InAppNavigationPageState extends State<InAppNavigationPage> {
  final _query = TextEditingController();
  final _mapController = MapController();
  Position? _position;
  LatLng? _destination;
  String? _destinationLabel;
  List<LatLng> _routePoints = [];
  List<NavigationStep> _steps = [];
  double? _distanceMeters;
  double? _durationSeconds;
  bool _busy = false;
  bool _guidance = false;
  int _nextStepIndex = 0;
  String _status = 'Getting your location';
  String? _error;
  StreamSubscription<Position>? _positionSubscription;
  static DateTime? _lastGeocodeRequest;
  static final Map<String, Map<String, dynamic>> _geocodeCache = {};
  String _tileUrlTemplate = defaultMapTileUrl;
  String _geocoderBaseUrl = defaultGeocoderBaseUrl;
  String _footRouterBaseUrl = defaultFootRouterBaseUrl;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery ?? '';
    _initialize();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tileUrlTemplate = preferences.getString('map_tiles_url') ?? defaultMapTileUrl;
      _geocoderBaseUrl = preferences.getString('map_geocoder_url') ?? defaultGeocoderBaseUrl;
      _footRouterBaseUrl = preferences.getString('map_foot_router_url') ?? defaultFootRouterBaseUrl;
    });
    final position = await getPosition();
    if (!mounted) return;
    if (position != null) {
      setState(() {
        _position = position;
        _status = 'Location ready';
      });
      _centerOn(position);
    } else {
      setState(() {
        _status = 'Location unavailable';
        _error = 'Turn on location and allow location permission to get a walking route.';
      });
    }
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (_) {
      if (mounted) {
        setState(() => _error = 'Live location updates are unavailable. You can still review the route.');
      }
    });

    if (widget.initialDestination != null) {
      _destination = widget.initialDestination;
      _destinationLabel = widget.initialDestinationLabel;
      await _fetchRoute();
    } else if (_query.text.trim().isNotEmpty) {
      await _searchAndRoute();
    }
  }

  void _centerOn(Position position) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      } catch (_) {
        // The controller might not be attached yet.
      }
    });
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);
    if (_guidance && _nextStepIndex < _steps.length) {
      final step = _steps[_nextStepIndex];
      final accuracy = position.accuracy.isFinite ? position.accuracy : 20.0;
      final threshold = math.max(20.0, accuracy);
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        step.location.latitude,
        step.location.longitude,
      );
      if (distance <= threshold) {
        _nextStepIndex++;
        if (_nextStepIndex >= _steps.length) {
          _finishGuidance();
        } else {
          _speakCurrentStep();
        }
      }
    }
  }

  Future<void> _searchAndRoute() async {
    if (_busy) return;
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter a place or address first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Searching for destination';
      _guidance = false;
      _routePoints = [];
      _steps = [];
    });
    try {
      // User-triggered only (never type-ahead); cache repeat searches in this app session.
      final cacheKey = '${_geocoderBaseUrl.toLowerCase()}|${query.toLowerCase()}';
      Map<String, dynamic>? result = _geocodeCache[cacheKey];
      if (result == null) {
        final previous = _lastGeocodeRequest;
        if (previous != null) {
          final elapsed = DateTime.now().difference(previous);
          if (elapsed < const Duration(seconds: 1)) {
            await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
          }
        }
        _lastGeocodeRequest = DateTime.now();
        final base = Uri.parse(_geocoderBaseUrl);
        final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
        final uri = base.replace(path: '$basePath/search', queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
        });
        final response = await http.get(uri, headers: {
          'User-Agent': 'BlindStick Companion/1.0 (+https://github.com/ShoninSelvaraj/Blind_Stick)',
        }).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw StateError('Place search is temporarily unavailable. Try again later.');
        }
        final results = jsonDecode(response.body) as List<dynamic>;
        if (results.isEmpty) {
          throw StateError('No place found. Try a nearby landmark or full address.');
        }
        result = results.first as Map<String, dynamic>;
        _geocodeCache[cacheKey] = result;
      }
      final latitude = double.tryParse(result['lat']?.toString() ?? '');
      final longitude = double.tryParse(result['lon']?.toString() ?? '');
      if (latitude == null || longitude == null) {
        throw StateError('The place search returned no usable coordinates.');
      }
      _destination = LatLng(latitude, longitude);
      _destinationLabel = (result['display_name'] ?? query).toString();
      await _loadRoute();
    } catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.toString().replaceFirst('Bad state: ', '');
          _status = 'Route unavailable';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchRoute() async {
    if (_destination == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Loading walking route';
      _guidance = false;
    });
    try {
      await _loadRoute();
    } catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.toString().replaceFirst('Bad state: ', '');
          _status = 'Route unavailable';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRoute() async {
    final start = _position ?? await getPosition();
    final target = _destination;
    if (start == null || target == null) {
      throw StateError('Current location or destination is unavailable.');
    }
    if (mounted) setState(() => _position = start);

    // OpenStreetMap's community foot-routing instance; no Google Maps SDK or key.
    final routerBase = Uri.parse(_footRouterBaseUrl);
    final routePath = '${routerBase.path.replaceAll(RegExp(r'/+$'), '')}/${start.longitude},${start.latitude};${target.longitude},${target.latitude}';
    final uri = routerBase.replace(path: routePath, queryParameters: {
      'overview': 'full',
      'geometries': 'geojson',
      'steps': 'true',
      'alternatives': 'false',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'BlindStick Companion/1.0 (+https://github.com/ShoninSelvaraj/Blind_Stick)',
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Walking directions are temporarily unavailable. Check your connection and try again.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) {
      throw StateError('No walking route was found for those points.');
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final points = coordinates.map((item) {
      final pair = item as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
    final legs = route['legs'] as List<dynamic>? ?? [];
    final rawSteps = legs.isEmpty ? <dynamic>[] : (legs.first['steps'] as List<dynamic>? ?? []);
    final steps = <NavigationStep>[];
    for (final raw in rawSteps) {
      final step = raw as Map<String, dynamic>;
      final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
      final location = maneuver['location'] as List<dynamic>?;
      if (location == null || location.length < 2) continue;
      steps.add(NavigationStep(
        instruction: _instructionFor(
          (maneuver['type'] ?? '').toString(),
          (maneuver['modifier'] ?? '').toString(),
          (step['name'] ?? '').toString(),
          maneuver['exit'] is num ? (maneuver['exit'] as num).toInt() : null,
        ),
        location: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
        distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
      ));
    }
    if (points.isEmpty || steps.isEmpty) {
      throw StateError('The routing service returned an incomplete route.');
    }
    if (!mounted) return;
    setState(() {
      _routePoints = points;
      _steps = steps;
      _distanceMeters = (route['distance'] as num?)?.toDouble();
      _durationSeconds = (route['duration'] as num?)?.toDouble();
      _status = 'Walking route ready';
      _nextStepIndex = steps.length > 1 ? 1 : 0;
      _guidance = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || points.isEmpty) return;
      try {
        _mapController.fitCamera(
          CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(36)),
        );
      } catch (_) {
        // The route and written instructions remain available if fitting fails.
      }
    });
    await stick.announce('Walking route found to ${_destinationLabel ?? 'your destination'}. ${_routeSummary()}');
  }

  String _instructionFor(String type, String modifier, String road, int? exit) {
    final street = road.isEmpty ? '' : ' onto $road';
    switch (type) {
      case 'depart':
        return 'Start walking${road.isEmpty ? '' : ' on $road'}.';
      case 'arrive':
        return 'You have arrived at your destination.';
      case 'roundabout':
      case 'rotary':
        return 'At the roundabout, take exit ${exit ?? 1}$street.';
      case 'merge':
        return 'Merge ${modifier.isEmpty ? 'ahead' : modifier}$street.';
      case 'fork':
        return 'At the fork, keep ${modifier.isEmpty ? 'straight' : modifier}$street.';
      case 'continue':
      case 'new name':
        return 'Continue walking$street.';
      case 'turn':
      case 'on ramp':
      case 'off ramp':
      case 'end of road':
      case 'notification':
        return 'Turn ${modifier.isEmpty ? 'ahead' : modifier}$street.';
      default:
        return 'Continue walking$street.';
    }
  }

  String _routeSummary() {
    final distance = _distanceMeters;
    final duration = _durationSeconds;
    if (distance == null || duration == null) return 'Follow the spoken directions and stay aware of your surroundings.';
    final distanceText = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} kilometres'
        : '${distance.round()} metres';
    return 'About $distanceText and ${(duration / 60).ceil()} minutes on the mapped route.';
  }

  Future<void> _startGuidance() async {
    if (_steps.isEmpty) return;
    setState(() {
      _guidance = true;
      _nextStepIndex = _steps.length > 1 ? 1 : 0;
    });
    await stick.announce('Spoken route guidance started. ${_routeSummary()}');
    if (_nextStepIndex < _steps.length) await _speakCurrentStep();
  }

  Future<void> _speakCurrentStep() async {
    if (!_guidance || _nextStepIndex >= _steps.length) return;
    await stick.announce('Next instruction. ${_steps[_nextStepIndex].instruction}');
  }

  Future<void> _finishGuidance() async {
    setState(() => _guidance = false);
    await stick.announce('You have reached the final mapped maneuver. Confirm your surroundings before proceeding.');
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _position == null
        ? const LatLng(20.5937, 78.9629)
        : LatLng(_position!.latitude, _position!.longitude);
    final markers = <Marker>[
      if (_position != null)
        Marker(
          point: LatLng(_position!.latitude, _position!.longitude),
          width: 48,
          height: 48,
          child: Semantics(label: 'Your current location', child: const Icon(Icons.my_location, color: Colors.blue, size: 34)),
        ),
      if (_destination != null)
        Marker(
          point: _destination!,
          width: 48,
          height: 48,
          child: Semantics(label: 'Destination', child: const Icon(Icons.location_pin, color: red, size: 40)),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walking navigation'),
        actions: [
          IconButton(
            tooltip: 'Accessibility settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
            icon: const Icon(Icons.accessibility_new),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.34,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: _position == null ? 5 : 15),
              children: [
                TileLayer(
                  urlTemplate: _tileUrlTemplate,
                  userAgentPackageName: 'com.vimal.blindstick',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [Polyline(points: _routePoints, strokeWidth: 5, color: teal)],
                  ),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Semantics(liveRegion: true, label: 'Navigation status: $_status', child: Text(_status, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy))),
                const SizedBox(height: 10),
                TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchAndRoute(),
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    hintText: 'Type a place or address; tap Search',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _searchAndRoute,
                    icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                    label: Text(_busy ? 'Finding route…' : 'Search and show route', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (_destinationLabel != null) ...[
                  const SizedBox(height: 12),
                  Text('Destination: $_destinationLabel', style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
                  if (_distanceMeters != null && _durationSeconds != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_routeSummary(), style: const TextStyle(fontSize: 16)),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: red, fontSize: 15))),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: _steps.isEmpty || _busy ? null : _startGuidance,
                    icon: Icon(_guidance ? Icons.volume_up : Icons.record_voice_over),
                    label: Text(_guidance ? 'Spoken guidance active' : 'Start spoken directions', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (_destination != null)
                  TextButton.icon(
                    onPressed: _busy ? null : _fetchRoute,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recalculate route from current location'),
                  ),
                const SizedBox(height: 10),
                const Text('Route instructions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: navy)),
                if (_steps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Search for a destination to show spoken instructions.'),
                  )
                else
                  ..._steps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    return Semantics(
                      label: 'Instruction ${index + 1}: ${step.instruction}',
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index == _nextStepIndex && _guidance ? teal : const Color(0xFFEAF7F4),
                          foregroundColor: navy,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(step.instruction),
                        subtitle: Text('Segment distance: ${step.distanceMeters.round()} metres'),
                        onTap: () => stick.announce(step.instruction),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                const Text(
                  'Accessibility and safety: spoken directions depend on GPS, network access, and this public routing service. The route is a guide, not a guarantee that a footpath or crossing is safe. Keep using your usual mobility method, confirm crossings with your established technique, and stop if the spoken location seems wrong.',
                  style: TextStyle(color: Color(0xFF59697B)),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://operations.osmfoundation.org/policies/tiles/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('OpenStreetMap tile usage policy'),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://operations.osmfoundation.org/policies/nominatim/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Destination-search usage policy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class PatientPage extends StatefulWidget{final AppUser user;const PatientPage({super.key,required this.user});@override State<PatientPage> createState()=>_PatientPageState();}
class _PatientPageState extends State<PatientPage>{final destination=TextEditingController();final api=ApiService.instance;Position? position;bool sharing=false,voice=true;Timer? locationTimer,pairExpiryTimer;String locationText='Location not checked yet';String? pairingCode;DateTime? pairingExpiresAt;bool generatingCode=false;bool? lastStoredConnection;
 @override void initState(){super.initState();_load();_ensurePatientRecord();stick.addListener(_changed);}
 Future<void> _ensurePatientRecord() async { try { final ref=FirebaseFirestore.instance.collection('patients').doc(widget.user.uid); final snap=await ref.get(); if(!snap.exists){ await ref.set({'ownerUid':widget.user.uid,'displayName':widget.user.name,'caregiverUids':<String>[],'deviceStatus':'not_connected','createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()}); } } catch (_) { /* Role assignment or Firestore rules may not be ready yet. */ } }
 Future<void> _generatePairingCode() async {
  if(generatingCode)return;
  setState(()=>generatingCode=true);
  try{
   final result=await PairingService.createCode(widget.user.uid);
   if(!mounted)return;
   setState(() { pairingCode=result.$1; pairingExpiresAt=result.$2; });
   pairExpiryTimer?.cancel();
   pairExpiryTimer=Timer(const Duration(minutes:10),(){
    if(mounted)setState(() { pairingCode=null; pairingExpiresAt=null; });
   });
   await stick.announce('Your caregiver pairing code is ${result.$1.split('').join(' ')}. It expires in ten minutes. Share it only with someone you trust.');
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not create a pairing code. Check your connection and Firestore rules.')));
  }finally{if(mounted)setState(()=>generatingCode=false);}
 }
 Widget _pairingCard(){
  final expired=pairingExpiresAt==null||pairingExpiresAt!.isBefore(DateTime.now());
  return Container(
   padding:const EdgeInsets.all(18),
   decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFDCE5E9))),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Row(children:[Icon(Icons.people_alt_outlined,color:teal,size:28),SizedBox(width:10),Expanded(child:Text('Connect someone you trust',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)))]),
    const SizedBox(height:8),
    const Text('Create a private one-time code for a caregiver. It expires in 10 minutes and can be used once. Up to two caregivers can be linked.',style:TextStyle(fontSize:14,color:Color(0xFF59697B))),
    const SizedBox(height:14),
    if(pairingCode!=null&&!expired)...[
     Semantics(liveRegion:true,label:'Caregiver pairing code: ${pairingCode!.split('').join(' ')}. Expires in ten minutes.',child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18,horizontal:12),decoration:BoxDecoration(color:pale,borderRadius:BorderRadius.circular(16)),child:Text(pairingCode!,textAlign:TextAlign.center,style:const TextStyle(fontSize:32,fontWeight:FontWeight.w900,letterSpacing:5,color:navy)))),
     const SizedBox(height:8),
     Row(children:[
      Expanded(child:OutlinedButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:pairingCode!)),icon:const Icon(Icons.copy),label:const Text('Copy code'))),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(onPressed:()=>stick.announce('Your pairing code is ${pairingCode!.split('').join(' ')}'),icon:const Icon(Icons.volume_up),label:const Text('Hear code'))),
     ]),
    ],
    SizedBox(width:double.infinity,height:52,child:FilledButton.icon(onPressed:generatingCode?null:_generatePairingCode,icon:generatingCode?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add_link),label:Text(pairingCode!=null&&!expired?'Create a new code':'Create pairing code',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)))),
   ]),
  );
 }
 Future<void> _load()async{final p=await SharedPreferences.getInstance();if(!mounted)return;setState(()=>voice=p.getBool('voice')??true);voiceGuidanceEnabled=voice;_refreshLocation();}
 void _changed(){if(!mounted)return;setState((){});if(lastStoredConnection!=stick.connected){lastStoredConnection=stick.connected;FirebaseFirestore.instance.collection('patients').doc(widget.user.uid).update({'deviceStatus':stick.connected?'connected':'disconnected','updatedAt':FieldValue.serverTimestamp()}).catchError((_){ });}}
 Future<void> _refreshLocation()async{final p=await getPosition();if(!mounted)return;setState(() { position=p; locationText=p==null?'Location unavailable':'Location ready · accuracy ${p.accuracy.round()} m'; });if(sharing&&p!=null)await api.location(widget.user.uid,p);}
 Future<void> _toggleSharing(bool v)async{setState(()=>sharing=v);locationTimer?.cancel();if(v){await _refreshLocation();locationTimer=Timer.periodic(const Duration(seconds:30),(_)=>_refreshLocation());}else{setState(()=>locationText='Location sharing paused');}}
 Future<void> _sos()async{
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
   title:const Text('Send emergency alert?'),
   content:const Text('This saves an SOS to the linked record. In zero-cost mode there is no automatic background push service. A connected caregiver can see the alert while their app is open. You can also open an SMS message and send it yourself.'),
   actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Save SOS'))],
  ));
  if(ok!=true)return;
  final p=position??await getPosition();
  final sent=await api.sos(widget.user.uid,p,'Patient requested emergency assistance');
  if(!mounted)return;
  final action=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
   title:Text(sent?'SOS saved':'SOS not saved'),
   content:Text(sent?'The alert is saved. It does not confirm that a caregiver has seen it or that emergency services were contacted. For immediate contact, choose Share by SMS and select your trusted contact.':'The alert could not be saved. Check your connection and Firestore access. If you need help now, contact your trusted person or emergency service using your usual method.'),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(c,'close'),child:const Text('Close')),
    if(sent)FilledButton.icon(onPressed:()=>Navigator.pop(c,'sms'),icon:const Icon(Icons.sms_outlined),label:const Text('Share by SMS')),
   ],
  ));
  if(action=='sms'&&sent){
   final coords=p==null?'Location unavailable':'Location: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
   final uri=Uri(scheme:'sms',queryParameters:{'body':'BlindStick Companion SOS: I need help. $coords. Please contact me.'});
   try{
    final opened=await launchUrl(uri,mode:LaunchMode.externalApplication);
    if(!opened&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No SMS app is available. Copy the SOS details and contact your trusted person manually.')));
   }catch(_){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open the SMS app. Contact your trusted person manually.')));
   }
  }
 }
 @override void dispose(){destination.dispose();locationTimer?.cancel();pairExpiryTimer?.cancel();stick.removeListener(_changed);super.dispose();}
 @override Widget build(BuildContext c){final t=stick.telemetry;return Scaffold(appBar:AppBar(title:const Text('My journey',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Accessibility settings',onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.accessibility_new)),TextButton.icon(onPressed:()=>confirmSignOut(c),icon:const Icon(Icons.logout),label:const Text('Sign out'))]),body:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,28),children:[
  Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Hello, ${widget.user.name}',style:const TextStyle(color:Colors.white70,fontSize:16)),const SizedBox(height:6),const Text('Ready when you are.',style:TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:14),Row(children:[Icon(stick.connected?Icons.bluetooth_connected:Icons.bluetooth_disabled,color:stick.connected?const Color(0xFF9FF0D0):Colors.orangeAccent),const SizedBox(width:8),Expanded(child:Text(stick.status,style:const TextStyle(color:Colors.white,fontSize:14)))])])),const SizedBox(height:16),
  Row(children:[Expanded(child:_statusTile('Obstacle range',t.distanceCm==null?'Waiting': '${t.distanceCm!.round()} cm',t.urgent?red:t.caution?Colors.orange:teal,Icons.radar)),const SizedBox(width:10),Expanded(child:_statusTile('Camera',t.receivedAt==null?'Waiting for stick':t.detectionStatus=='model_not_installed'?'AI model not installed':t.object!='Waiting for device data'?t.object:t.cameraFrameAvailable==true?'Camera active; no detection model':'Camera unavailable',teal,Icons.camera_alt_outlined))]),const SizedBox(height:12),
  if(stick.lastError!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFF1F0),borderRadius:BorderRadius.circular(14)),child:Text(stick.lastError!,style:const TextStyle(color:red))),
  SizedBox(height:56,child:FilledButton.icon(onPressed:stick.scanning?null:stick.scanAndConnect,icon:Icon(stick.scanning?Icons.hourglass_top:Icons.bluetooth_searching),label:Text(stick.scanning?'Searching…':stick.connected?'Reconnect to stick':'Find my stick',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)))),const SizedBox(height:10),
  SizedBox(height:62,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:stick.assistance?red:teal,foregroundColor:Colors.white),onPressed:stick.connected?()=>stick.setAssistance(!stick.assistance):null,icon:Icon(stick.assistance?Icons.pause_circle_filled:Icons.play_circle_fill,size:28),label:Text(stick.assistance?'Pause assistance':'Start assistance',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)))),if(!stick.connected)const Padding(padding:EdgeInsets.only(top:8),child:Text('Connect the physical stick before starting live assistance.',style:TextStyle(color:Color(0xFF64748B)))),const SizedBox(height:18),_pairingCard(),const SizedBox(height:22),
  _section('Get somewhere',Icons.navigation_outlined),const SizedBox(height:10),TextField(controller:destination,textInputAction:TextInputAction.go,onSubmitted:(v)=>openNavigation(c,v),decoration:const InputDecoration(labelText:'Where would you like to go?',hintText:'Enter a place or address',prefixIcon:Icon(Icons.place_outlined))),const SizedBox(height:10),SizedBox(height:54,child:FilledButton.icon(onPressed:()=>openNavigation(c,destination.text),icon:const Icon(Icons.directions_walk),label:const Text('Start walking directions',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)))),const SizedBox(height:8),Text(locationText,style:const TextStyle(color:Color(0xFF64748B))),TextButton.icon(onPressed:_refreshLocation,icon:const Icon(Icons.my_location),label:const Text('Check my location')),const SizedBox(height:20),
  _section('Keep your caregiver informed',Icons.favorite_outline),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Share my location',style:TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(sharing?'Updates location every 30 seconds while the app is open':'Off until you choose to share'),value:sharing,onChanged:_toggleSharing),const SizedBox(height:10),
  SizedBox(height:62,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white),onPressed:_sos,icon:const Icon(Icons.sos,size:30),label:const Text('SOS · Ask for help',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)))),const SizedBox(height:20),
  _section('Recent alerts',Icons.notifications_active_outlined),const SizedBox(height:8),if(stick.events.isEmpty)const Text('Your device events will appear here after connection.')else ...stick.events.take(8).map((e)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.circle,size:10,color:teal),title:Text(e,style:const TextStyle(fontSize:14))))
 ]));}
 Widget _statusTile(String title,String value,Color color,IconData icon)=>Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFE1E8EE))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:25),const SizedBox(height:12),Text(title,style:const TextStyle(color:Color(0xFF68778A))),const SizedBox(height:4),Text(value,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:navy,fontWeight:FontWeight.w900,fontSize:17))]));
 Widget _section(String s,IconData i)=>Row(children:[Icon(i,color:teal),const SizedBox(width:8),Text(s,style:const TextStyle(color:navy,fontSize:19,fontWeight:FontWeight.w900))]);
}

class CaregiverPage extends StatefulWidget{
 final AppUser user;const CaregiverPage({super.key,required this.user});
 @override State<CaregiverPage> createState()=>_CaregiverPageState();
}
class _CaregiverPageState extends State<CaregiverPage>{
 final codeController=TextEditingController();bool pairing=false;String? pairingError,pairingInfo;
 @override void dispose(){codeController.dispose();super.dispose();}
 Future<void> _pair()async{
  if(pairing)return;
  final code=codeController.text.replaceAll(RegExp(r'\s+'),'');
  if(!RegExp(r'^\d{8}$').hasMatch(code)){setState(()=>pairingError='Enter all 8 digits from the code shared with you.');return;}
  setState(() { pairing=true; pairingError=null; pairingInfo=null; });
  try{
   await PairingService.redeemCode(code,widget.user.uid);
   if(mounted)setState(()=>pairingInfo='Connected. You can now see updates that the person chooses to share.');
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Pairing complete.')));
  }catch(e){
   if(mounted)setState(()=>pairingError=e.toString().replaceFirst('Bad state: ',''));
  }finally{if(mounted)setState(()=>pairing=false);}
 }
 @override Widget build(BuildContext c)=>Scaffold(
  appBar:AppBar(title:const Text('Support',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Accessibility settings',onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.accessibility_new)),TextButton.icon(onPressed:()=>confirmSignOut(c),icon:const Icon(Icons.logout),label:const Text('Sign out'))]),
  body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
   stream:FirebaseFirestore.instance.collection('pairingClaims').doc(widget.user.uid).snapshots(),
   builder:(context,claimSnapshot){
    if(claimSnapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
    final claim=claimSnapshot.data?.data();
    if(claim==null){return ListView(padding:const EdgeInsets.all(20),children:[
     Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.favorite_outline,color:Color(0xFF9FF0D0),size:36),SizedBox(height:14),
      Text('Stay connected, with permission.',style:TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),
      SizedBox(height:8),Text('Enter the one-time code shared by the person using BlindStick Companion. They control who can connect.',style:TextStyle(color:Colors.white70,fontSize:15))
     ])),
     const SizedBox(height:22),const Text('Pair with someone',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),
     TextField(controller:codeController,keyboardType:TextInputType.number,maxLength:8,autofillHints:const [],textInputAction:TextInputAction.done,onSubmitted:(_)=>_pair(),decoration:const InputDecoration(labelText:'8-digit pairing code',hintText:'Enter the shared code',prefixIcon:Icon(Icons.key_outlined))),
     if(pairingError!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(pairingError!,style:const TextStyle(color:red))),
     if(pairingInfo!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(pairingInfo!,style:const TextStyle(color:teal))),
     const SizedBox(height:8),SizedBox(height:56,child:FilledButton.icon(onPressed:pairing?null:_pair,icon:pairing?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.link),label:Text(pairing?'Connecting…':'Connect securely',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800)))),
     const SizedBox(height:16),const Text('Codes expire after 10 minutes and work once. An account can connect to one patient at a time in this version.',style:TextStyle(color:Color(0xFF64748B))),
    ]);}
    final patientUid=(claim['patientUid']??'').toString();
    return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
     stream:FirebaseFirestore.instance.collection('patients').doc(patientUid).snapshots(),
     builder:(context,patientSnapshot){
      if(patientSnapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      final patient=patientSnapshot.data?.data();
      if(patient==null)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Patient information is not available. Check the pairing.',textAlign:TextAlign.center)));
      final location=patient['lastLocation'];
      final lat=location is Map&&location['latitude'] is num?(location['latitude'] as num).toDouble():null;
      final lon=location is Map&&location['longitude'] is num?(location['longitude'] as num).toDouble():null;
      final name=(patient['displayName']??'Your person').toString();
      return ListView(padding:const EdgeInsets.all(20),children:[
       Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Icon(Icons.health_and_safety_outlined,color:Color(0xFF9FF0D0),size:36),const SizedBox(height:14),
        Text('Connected to $name',style:const TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),const Text('You are linked with permission. Updates appear here when they are shared.',style:TextStyle(color:Colors.white70,fontSize:15))
       ])),
       const SizedBox(height:20),const Text('Stick connection',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),Text('Status: ${(patient['deviceStatus']??'unknown').toString().replaceAll('_',' ')}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:navy)),const SizedBox(height:16),const Text('Latest shared location',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),
       Text(lat==null?'No location has been shared yet.': 'Coordinates: ${lat.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}',style:const TextStyle(fontSize:16)),
       if(location is Map&&location['recordedAt'] is Timestamp)Padding(padding:const EdgeInsets.only(top:4),child:Text('Updated ${(location['recordedAt'] as Timestamp).toDate().toLocal()}',style:const TextStyle(color:Color(0xFF64748B)))),
       const SizedBox(height:12),SizedBox(height:52,child:OutlinedButton.icon(onPressed:lat==null||lon==null?null:()=>_openLastLocation(lat,lon),icon:const Icon(Icons.map_outlined),label:const Text('Open location in Maps'))),
       const SizedBox(height:22),const Text('Recent alerts',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),
       StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:FirebaseFirestore.instance.collection('patients').doc(patientUid).collection('alerts').orderBy('createdAt',descending:true).limit(8).snapshots(),
        builder:(context,alerts){
         if(alerts.hasError)return const Text('Alerts could not be loaded. Check your connection and access permissions.');
         if(alerts.connectionState==ConnectionState.waiting)return const LinearProgressIndicator();
         if(alerts.data!.docs.isEmpty)return const Text('No alerts have been recorded.');
         return Column(children:alerts.data!.docs.map((doc){
          final d=doc.data();final type=(d['type']??'Update').toString();final message=(d['message']??'').toString();
          final isSos=type=='sos';
          return ListTile(contentPadding:EdgeInsets.zero,leading:Icon(isSos?Icons.sos:Icons.notifications_outlined,color:isSos?red:teal),title:Text(isSos?'Emergency alert':type),subtitle:Text(message),isThreeLine:message.length>48);
         }).toList());
        }),
       const SizedBox(height:12),const Text('If an emergency alert appears, contact the person or local emergency services as appropriate. A screen update does not confirm that help has been dispatched.',style:TextStyle(color:Color(0xFF64748B))),
      ]);
     });
   }),
 );
 Future<void> _openLastLocation(double lat,double lon)async{
  await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>InAppNavigationPage(initialDestination:LatLng(lat,lon),initialDestinationLabel:'Shared patient location')));
 }
}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{
 bool voice=true,highContrast=false;double textScale=1.0;String? saved;
 final tileUrlController=TextEditingController(text:defaultMapTileUrl);
 final geocoderUrlController=TextEditingController(text:defaultGeocoderBaseUrl);
 final footRouterUrlController=TextEditingController(text:defaultFootRouterBaseUrl);
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{
  final prefs=await SharedPreferences.getInstance();if(!mounted)return;
  tileUrlController.text=prefs.getString('map_tiles_url')??defaultMapTileUrl;
  geocoderUrlController.text=prefs.getString('map_geocoder_url')??defaultGeocoderBaseUrl;
  footRouterUrlController.text=prefs.getString('map_foot_router_url')??defaultFootRouterBaseUrl;
  setState(() { voice=prefs.getBool('voice')??true; textScale=prefs.getDouble('text_scale')??1.0; highContrast=prefs.getBool('high_contrast')??false; });
  voiceGuidanceEnabled=voice;appTextScale.value=textScale;appHighContrast.value=highContrast;
 }
 Future<void> _saveVoice(bool value)async{
  setState(()=>voice=value);voiceGuidanceEnabled=value;
  final prefs=await SharedPreferences.getInstance();await prefs.setBool('voice',value);
 }
 Future<void> _saveTextScale(double value)async{
  setState(()=>textScale=value);appTextScale.value=value;
  final prefs=await SharedPreferences.getInstance();await prefs.setDouble('text_scale',value);
 }
 Future<void> _saveHighContrast(bool value)async{
  setState(()=>highContrast=value);appHighContrast.value=value;
  final prefs=await SharedPreferences.getInstance();await prefs.setBool('high_contrast',value);
 }
 Future<void> _saveMapServices() async {
  final tiles=tileUrlController.text.trim();
  final geocoder=Uri.tryParse(geocoderUrlController.text.trim());
  final router=Uri.tryParse(footRouterUrlController.text.trim());
  if(!tiles.contains('{z}')||!tiles.contains('{x}')||!tiles.contains('{y}')||
     geocoder==null||!geocoder.hasScheme||geocoder.host.isEmpty||
     router==null||!router.hasScheme||router.host.isEmpty) {
    setState(()=>saved='Check the tile template and enter valid geocoder/router base URLs.');
    return;
  }
  final prefs=await SharedPreferences.getInstance();
  await prefs.setString('map_tiles_url',tiles);
  await prefs.setString('map_geocoder_url',geocoder.toString().replaceAll(RegExp(r'/+$'),''));
  await prefs.setString('map_foot_router_url',router.toString().replaceAll(RegExp(r'/+$'),''));
  if(mounted)setState(()=>saved='Map service settings saved on this phone. Reopen navigation to use them.');
 }
 @override void dispose(){
  tileUrlController.dispose();geocoderUrlController.dispose();footRouterUrlController.dispose();super.dispose();
 }
 @override Widget build(BuildContext c)=>Scaffold(
  appBar:AppBar(title:const Text('Accessibility & settings')),
  body:ListView(padding:const EdgeInsets.all(20),children:[
   const Text('Set BlindStick Companion up for you',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:navy)),
   const SizedBox(height:8),const Text('These controls work on this phone and are saved automatically.'),
   const SizedBox(height:24),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Spoken safety guidance',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:const Text('Speak warnings and important status messages'),value:voice,onChanged:_saveVoice),
   const SizedBox(height:10),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('High contrast',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:const Text('Use a black-and-white colour scheme for low vision'),value:highContrast,onChanged:_saveHighContrast),
   const SizedBox(height:22),
   const Text('Text size',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:navy)),
   const SizedBox(height:4),const Text('Make labels and instructions easier to read. Android display and TalkBack settings also continue to work.'),
   Slider(value:textScale,min:1.0,max:1.6,divisions:6,label:'${(textScale*100).round()}%',onChanged:_saveTextScale),
   Center(child:Text('${(textScale*100).round()}% text size',style:TextStyle(fontSize:16*textScale,fontWeight:FontWeight.w800,color:navy))),
   const SizedBox(height:18),
   ExpansionTile(
    title:const Text('Map services (advanced)',style:TextStyle(fontWeight:FontWeight.w800)),
    subtitle:const Text('Change map/search/routing servers without updating the app'),
    children:[
     TextField(controller:tileUrlController,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Map tile URL template',helperText:'Must include {z}, {x}, and {y}')),
     const SizedBox(height:10),
     TextField(controller:geocoderUrlController,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Geocoder base URL',helperText:'The app adds /search and query parameters')),
     const SizedBox(height:10),
     TextField(controller:footRouterUrlController,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Foot-routing URL prefix',helperText:'Must end with an OSRM-compatible /route/v1/driving endpoint')),
     const SizedBox(height:10),
     SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_saveMapServices,icon:const Icon(Icons.save_outlined),label:const Text('Save map service settings'))),
     if(saved!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(saved!,style:const TextStyle(color:navy))),
     const Padding(padding:EdgeInsets.only(bottom:8),child:Text('Use servers whose terms you have checked. Public community services are best-effort and rate-limited.',style:TextStyle(color:Color(0xFF59697B)))),
    ],
   ),
   const SizedBox(height:22),
   OutlinedButton.icon(onPressed:()=>stick.announce('BlindStick Companion voice test. If you can hear this message, spoken safety guidance is working.'),icon:const Icon(Icons.volume_up_outlined),label:const Text('Test spoken guidance')),
   const SizedBox(height:12),OutlinedButton.icon(onPressed:()=>confirmSignOut(c),icon:const Icon(Icons.logout),label:const Text('Sign out')),
   const SizedBox(height:24),const Text('Bluetooth connection',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),
   const SizedBox(height:8),const Text('The stick must advertise the BlindStick Companion BLE service. If it is not found, check that it is powered on and has the matching firmware. Camera AI and obstacle measurements are shown only when the hardware sends real results.'),
   const SizedBox(height:20),const Text('Safety note',style:TextStyle(color:Color(0xFF64748B))),
   const Text('BlindStick Companion is a companion prototype, not a certified mobility aid. Keep using your usual mobility skills and emergency arrangements. The app cannot guarantee GPS accuracy, network availability or emergency delivery.',style:TextStyle(color:Color(0xFF64748B))),
  ]));
}
