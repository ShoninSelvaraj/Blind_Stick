import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); await Firebase.initializeApp(); runApp(const BlindStickApp()); }

const navy = Color(0xFF17233B);
const teal = Color(0xFF007F78);
const pale = Color(0xFFEAF7F4);
const red = Color(0xFFB42318);
const serviceUuid = '7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001';
const telemetryUuid = '7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001';
const commandUuid = '7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001';
bool voiceGuidanceEnabled = true;
final ValueNotifier<double> appTextScale = ValueNotifier<double>(1.0);

class BlindStickApp extends StatelessWidget {
  const BlindStickApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Saathi', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: teal), scaffoldBackgroundColor: const Color(0xFFF7FAFC), fontFamily: 'Roboto',
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))), contentPadding: const EdgeInsets.all(16))),
    home: const AuthGate(),
    builder: (context, child) => ValueListenableBuilder<double>(
      valueListenable: appTextScale,
      builder: (context, scale, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child ?? const SizedBox.shrink(),
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
 Text('Signed in as $email. Your account profile is not ready. Sign out and try again, or contact support if this continues.',textAlign:TextAlign.center,style:const TextStyle(fontSize:16)),const SizedBox(height:22),FilledButton.icon(onPressed:()=>FirebaseAuth.instance.signOut(),icon:const Icon(Icons.logout),label:const Text('Sign out'))
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
   if(mounted)setState(()=>error=switch(ex.code){
    'invalid-email'=>'That email address is not valid.','user-not-found'=>'No account exists for this email. Choose Create account first.',
    'wrong-password'||'invalid-credential'=>'Email or password is incorrect.','email-already-in-use'=>'An account already exists for this email. Sign in instead.',
    'weak-password'=>'Choose a stronger password.','network-request-failed'=>'No network connection. Check internet and try again.',
    'too-many-requests'=>'Too many attempts. Wait a little before trying again.',_=>'Could not authenticate (${ex.code}). Check Firebase Authentication settings.'});
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
 const SizedBox(height:20),const Text('Saathi',style:TextStyle(fontSize:38,fontWeight:FontWeight.w900,color:navy)),const Text('Your companion for safer journeys',style:TextStyle(fontSize:17,color:Color(0xFF59697B))),const SizedBox(height:32),
 Text(createAccount?'Create your account':'Welcome back',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:16),
 if(createAccount)...[
  const Text('Choose what you want to do with Saathi',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:navy)),
  const SizedBox(height:12),
  _roleChoice(Role.patient,'Use my Saathi stick','Navigate, hear safety alerts and ask for help.',Icons.accessibility_new_rounded),
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
 double? distanceCm; String object='Waiting for device data'; String signal='unknown'; int? battery; bool? trafficWalk; String crowd='unknown'; DateTime? receivedAt;
 bool get urgent=>distanceCm!=null&&distanceCm!<35;
 bool get caution=>distanceCm!=null&&distanceCm!<90;
 void fromJson(Map<String,dynamic> j){
  final d=j['distance_cm']??j['distanceCm']??j['distance']; if(d is num)distanceCm=d.toDouble();
  object=(j['object']??j['detected_object']??j['label']??object).toString(); signal=(j['signal']??signal).toString();
  final b=j['battery']??j['battery_percent']; if(b is num)battery=b.toInt();
  if(j['traffic_walk'] is bool)trafficWalk=j['traffic_walk'];
  if(j['crowd']!=null)crowd=j['crowd'].toString(); receivedAt=DateTime.now();
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
   final patientSnap=await tx.get(patientRef);
   if(!patientSnap.exists)throw StateError('The linked account is not ready yet. Ask them to open the app and try again.');
   final patientData=patientSnap.data()!;
   final caregivers=List<String>.from(patientData['caregiverUids']??const <String>[]);
   if(caregivers.contains(caregiverUid))throw StateError('You are already linked to this person.');
   if(caregivers.length>=2)throw StateError('This person has reached the limit of two caregivers.');
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
 final FlutterTts tts=FlutterTts(); final StickTelemetry telemetry=StickTelemetry(); BluetoothDevice? device; BluetoothCharacteristic? telemetryChar, commandChar; StreamSubscription<List<ScanResult>>? scanSub; StreamSubscription<List<int>>? notifySub; StreamSubscription<BluetoothConnectionState>? connectionSub; StreamSubscription<BluetoothAdapterState>? adapterSub;
 bool scanning=false,connected=false,assistance=false; String status='Stick not connected'; String? lastError; final List<String> events=[]; DateTime? lastSpoken; String _lastWarning=''; String _packetBuffer='';
 BleStickService(){tts.setLanguage('en-IN');tts.setSpeechRate(0.46);}
 Future<void> scanAndConnect() async {
  if(scanning)return; scanning=true;status='Looking for your stick';lastError=null;notifyListeners();
  try{
   final scanPermission=await Permission.bluetoothScan.request();
   final connectPermission=await Permission.bluetoothConnect.request();
   if(!scanPermission.isGranted||!connectPermission.isGranted){status='Bluetooth permission needed';lastError='Allow Bluetooth access in Android settings to find the stick.';return;}
   final state=await FlutterBluePlus.adapterState.first; if(state!=BluetoothAdapterState.on){status='Please turn Bluetooth on';lastError='Bluetooth is off';scanning=false;notifyListeners();return;}
   await FlutterBluePlus.startScan(timeout:const Duration(seconds:12),withServices:[Guid(serviceUuid)]);
   final results=await FlutterBluePlus.scanResults.firstWhere((r)=>r.any((x)=>x.advertisementData.serviceUuids.any((g)=>g==Guid(serviceUuid)))).timeout(const Duration(seconds:12),onTimeout:()=> <ScanResult>[]);
   final match=results.where((x)=>x.advertisementData.serviceUuids.any((g)=>g==Guid(serviceUuid))).toList();
   if(match.isEmpty){status='Stick not found';lastError='No device advertising the Saathi service was found. Check that the stick is powered on and running the matching firmware.';return;}
   device=match.first.device; await device!.connect(timeout:const Duration(seconds:15));
   connectionSub?.cancel();connectionSub=device!.connectionState.listen((s){connected=s==BluetoothConnectionState.connected;if(!connected){assistance=false;status='Connection lost — stick alerts may be unavailable';_event('Connection lost');}else{status='Stick connected';_event('Stick connected');}notifyListeners();});
   final services=await device!.discoverServices(); BluetoothService? svc;
   for(final s in services){if(s.serviceUuid==Guid(serviceUuid)){svc=s;break;}}
   if(svc==null)throw Exception('Firmware service UUID does not match the app.');
   for(final ch in svc.characteristics){if(ch.characteristicUuid==Guid(telemetryUuid))telemetryChar=ch;if(ch.characteristicUuid==Guid(commandUuid))commandChar=ch;}
   if(telemetryChar==null)throw Exception('Telemetry characteristic is missing.');
   await telemetryChar!.setNotifyValue(true); notifySub?.cancel();notifySub=telemetryChar!.onValueReceived.listen(_handlePacket);
   status='Stick connected';lastError=null;await _command({'cmd':'hello','protocol':1});
  }catch(e){status='Could not connect';lastError=e.toString().replaceFirst('Exception: ','');connected=false;}
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
  if(t.distanceCm!=null&&t.distanceCm!<35)warning='Stop. Obstacle very close.';
  else if(t.trafficWalk==false&&t.object.toLowerCase().contains('traffic'))warning='Stop. Do not cross yet. Check the crossing yourself.';
  else if(t.distanceCm!=null&&t.distanceCm!<90)warning='Caution. Obstacle ahead.';
  else if(t.crowd.toLowerCase()=='high')warning='Crowded area ahead. Slow down.';
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
 @override void dispose(){scanSub?.cancel();notifySub?.cancel();connectionSub?.cancel();adapterSub?.cancel();device?.disconnect();tts.stop();super.dispose();}
}
final stick=BleStickService();

Future<Position?> getPosition()async{try{if(!await Geolocator.isLocationServiceEnabled())return null;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)return null;return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:15)));}catch(_){return null;}}
Future<void> openNavigation(BuildContext context,String destination) async {
 void showMessage(String message){if(!context.mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
 final place=destination.trim();
 if(place.isEmpty){showMessage('Please enter a destination first.');return;}
 final q=Uri.encodeComponent(place);
 // Hand off immediately to Google Maps navigation; Maps obtains its own live GPS fix.
 // This avoids blocking the app on a slow location request before directions open.
 final nativeRoute=Uri.parse('google.navigation:q=$q&mode=w');
 final webRoute=Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q&travelmode=walking&dir_action=navigate');
 try{
  var opened=await launchUrl(nativeRoute,mode:LaunchMode.externalApplication);
  if(!opened)opened=await launchUrl(webRoute,mode:LaunchMode.externalApplication);
  if(!opened)showMessage('Could not open navigation. Install or enable Google Maps and check your internet connection.');
 }catch(_){showMessage('Could not open navigation. Check that a maps app is installed and internet is available.');}
}

class PatientPage extends StatefulWidget{final AppUser user;const PatientPage({super.key,required this.user});@override State<PatientPage> createState()=>_PatientPageState();}
class _PatientPageState extends State<PatientPage>{final destination=TextEditingController();final api=ApiService.instance;Position? position;bool sharing=false,voice=true;Timer? locationTimer,pairExpiryTimer;String locationText='Location not checked yet';String? pairingCode;DateTime? pairingExpiresAt;bool generatingCode=false;
 @override void initState(){super.initState();_load();_ensurePatientRecord();stick.addListener(_changed);}
 Future<void> _ensurePatientRecord() async { try { final ref=FirebaseFirestore.instance.collection('patients').doc(widget.user.uid); final snap=await ref.get(); if(!snap.exists){ await ref.set({'ownerUid':widget.user.uid,'displayName':widget.user.name,'caregiverUids':<String>[],'deviceStatus':'not_connected','createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()}); } } catch (_) { /* Role assignment or Firestore rules may not be ready yet. */ } }
 Future<void> _generatePairingCode() async {
  if(generatingCode)return;
  setState(()=>generatingCode=true);
  try{
   final result=await PairingService.createCode(widget.user.uid);
   if(!mounted)return;
   setState(()=>{pairingCode=result.$1,pairingExpiresAt=result.$2});
   pairExpiryTimer?.cancel();
   pairExpiryTimer=Timer(const Duration(minutes:10),(){
    if(mounted)setState(()=>{pairingCode=null,pairingExpiresAt=null});
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
    Row(children:[const Icon(Icons.people_alt_outlined,color:teal,size:28),const SizedBox(width:10),Expanded(child:Text('Connect someone you trust',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)))]),
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
 void _changed(){if(!mounted)return;setState((){});}
 Future<void> _refreshLocation()async{final p=await getPosition();if(!mounted)return;setState(() { position=p; locationText=p==null?'Location unavailable':'Location ready · accuracy ${p.accuracy.round()} m'; });if(sharing&&p!=null)await api.location(widget.user.uid,p);}
 Future<void> _toggleSharing(bool v)async{setState(()=>sharing=v);locationTimer?.cancel();if(v){await _refreshLocation();locationTimer=Timer.periodic(const Duration(seconds:30),(_)=>_refreshLocation());}else{setState(()=>locationText='Location sharing paused');}}
 Future<void> _sos()async{final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Send emergency alert?'),content:const Text('This will save an SOS alert to your linked patient record in Firestore. A caregiver can see it when they refresh or while viewing alerts; push notifications are not configured yet.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Send SOS'))]));if(ok!=true)return;final p=position??await getPosition();final sent=await api.sos(widget.user.uid,p,'Patient requested emergency assistance');if(!mounted)return;await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(sent?'SOS submitted':'SOS not delivered'),content:Text(sent?'The alert was saved to Firestore. This does not confirm that a caregiver has seen it. Use your usual emergency contact method too if you are in danger.':'The alert could not be saved. Check internet and Firestore permissions, or call your emergency contact directly.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('OK'))]));}
 @override void dispose(){destination.dispose();locationTimer?.cancel();pairExpiryTimer?.cancel();stick.removeListener(_changed);super.dispose();}
 @override Widget build(BuildContext c){final t=stick.telemetry;return Scaffold(appBar:AppBar(title:const Text('Saathi · My journey',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Settings',onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SettingsPage())),icon:const Icon(Icons.settings_outlined))]),body:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,28),children:[
  Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Hello, ${widget.user.name}',style:const TextStyle(color:Colors.white70,fontSize:16)),const SizedBox(height:6),const Text('Ready when you are.',style:TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:14),Row(children:[Icon(stick.connected?Icons.bluetooth_connected:Icons.bluetooth_disabled,color:stick.connected?const Color(0xFF9FF0D0):Colors.orangeAccent),const SizedBox(width:8),Expanded(child:Text(stick.status,style:const TextStyle(color:Colors.white,fontSize:14)))])])),const SizedBox(height:16),
  Row(children:[Expanded(child:_statusTile('Obstacle range',t.distanceCm==null?'Waiting': '${t.distanceCm!.round()} cm',t.urgent?red:t.caution?Colors.orange:teal,Icons.radar)),const SizedBox(width:10),Expanded(child:_statusTile('Camera',t.receivedAt==null?'No data':t.object,teal,Icons.camera_alt_outlined))]),const SizedBox(height:12),
  if(stick.lastError!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFF1F0),borderRadius:BorderRadius.circular(14)),child:Text(stick.lastError!,style:const TextStyle(color:red))),
  SizedBox(height:56,child:FilledButton.icon(onPressed:stick.scanning?null:stick.scanAndConnect,icon:Icon(stick.scanning?Icons.hourglass_top:Icons.bluetooth_searching),label:Text(stick.scanning?'Searching…':stick.connected?'Reconnect to stick':'Find my stick',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)))),const SizedBox(height:10),
  SizedBox(height:62,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:stick.assistance?red:teal,foregroundColor:Colors.white),onPressed:stick.connected?()=>stick.setAssistance(!stick.assistance):null,icon:Icon(stick.assistance?Icons.pause_circle_filled:Icons.play_circle_fill,size:28),label:Text(stick.assistance?'Pause assistance':'Start assistance',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)))),if(!stick.connected)const Padding(padding:EdgeInsets.only(top:8),child:Text('Connect the physical stick before starting live assistance.',style:TextStyle(color:Color(0xFF64748B)))),const SizedBox(height:18),_pairingCard(),const SizedBox(height:22),
  _section('Get somewhere',Icons.navigation_outlined),const SizedBox(height:10),TextField(controller:destination,textInputAction:TextInputAction.go,onSubmitted:(v)=>openNavigation(c,v),decoration:const InputDecoration(labelText:'Where would you like to go?',hintText:'Enter a place or address',prefixIcon:Icon(Icons.place_outlined))),const SizedBox(height:10),SizedBox(height:54,child:FilledButton.icon(onPressed:()=>openNavigation(c,destination.text),icon:const Icon(Icons.directions_walk),label:const Text('Start walking directions',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)))),const SizedBox(height:8),Text(locationText,style:const TextStyle(color:Color(0xFF64748B))),TextButton.icon(onPressed:_refreshLocation,icon:const Icon(Icons.my_location),label:const Text('Check my location')),const SizedBox(height:20),
  _section('Keep your caregiver informed',Icons.favorite_outline),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Share my location',style:TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(sharing?'Attempts an update every 30 seconds when the backend is configured':'Off until you choose to share'),value:sharing,onChanged:_toggleSharing),const SizedBox(height:10),
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
  setState(()=>{pairing=true,pairingError=null,pairingInfo=null});
  try{
   await PairingService.redeemCode(code,widget.user.uid);
   if(mounted)setState(()=>pairingInfo='Connected. You can now see updates that the person chooses to share.');
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Pairing complete.')));
  }catch(e){
   if(mounted)setState(()=>pairingError=e.toString().replaceFirst('Bad state: ',''));
  }finally{if(mounted)setState(()=>pairing=false);}
 }
 @override Widget build(BuildContext c)=>Scaffold(
  appBar:AppBar(title:const Text('Saathi · Support',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Settings and accessibility',onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.settings_outlined))]),
  body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
   stream:FirebaseFirestore.instance.collection('pairingClaims').doc(widget.user.uid).snapshots(),
   builder:(context,claimSnapshot){
    if(claimSnapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
    final claim=claimSnapshot.data?.data();
    if(claim==null)return ListView(padding:const EdgeInsets.all(20),children:[
     Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.favorite_outline,color:Color(0xFF9FF0D0),size:36),SizedBox(height:14),
      Text('Stay connected, with permission.',style:TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),
      SizedBox(height:8),Text('Enter the one-time code shared by the person using Saathi. They control who can connect.',style:TextStyle(color:Colors.white70,fontSize:15))
     ])),
     const SizedBox(height:22),const Text('Pair with someone',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),
     TextField(controller:codeController,keyboardType:TextInputType.number,maxLength:8,autofillHints:const [],textInputAction:TextInputAction.done,onSubmitted:(_)=>_pair(),decoration:const InputDecoration(labelText:'8-digit pairing code',hintText:'Enter the shared code',prefixIcon:Icon(Icons.key_outlined))),
     if(pairingError!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(pairingError!,style:const TextStyle(color:red))),
     if(pairingInfo!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(pairingInfo!,style:const TextStyle(color:teal))),
     const SizedBox(height:8),SizedBox(height:56,child:FilledButton.icon(onPressed:pairing?null:_pair,icon:pairing?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.link),label:Text(pairing?'Connecting…':'Connect securely',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800)))),
     const SizedBox(height:16),const Text('Codes expire after 10 minutes and work once. An account can connect to one patient at a time in this version.',style:TextStyle(color:Color(0xFF64748B))),
    ]);
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
        const SizedBox(height:8),Text('You are linked with permission. Updates appear here when they are shared.',style:const TextStyle(color:Colors.white70,fontSize:15))
       ])),
       const SizedBox(height:20),const Text('Latest shared location',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),
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
          return ListTile(contentPadding:EdgeInsets.zero,leading:Icon(isSos?Icons.sos:Icons.notifications_outlined,color:isSos?red:teal),title:Text(isSos?'Emergency alert':'$type'),subtitle:Text(message),isThreeLine:message.length>48);
         }).toList());
        }),
       const SizedBox(height:12),const Text('If an emergency alert appears, contact the person or local emergency services as appropriate. A screen update does not confirm that help has been dispatched.',style:TextStyle(color:Color(0xFF64748B))),
      ]);
     });
   }),
 );
 Future<void> _openLastLocation(double lat,double lon)async{
  final url=Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
  try{final opened=await launchUrl(url,mode:LaunchMode.externalApplication);if(!opened&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open Maps.')));}
  catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open Maps.')));}
 }
}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{
 bool voice=true;double textScale=1.0;String? saved;
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{
  final prefs=await SharedPreferences.getInstance();if(!mounted)return;
  setState(()=>{voice=prefs.getBool('voice')??true,textScale=prefs.getDouble('text_scale')??1.0});
  voiceGuidanceEnabled=voice;appTextScale.value=textScale;
 }
 Future<void> _saveVoice(bool value)async{
  setState(()=>voice=value);voiceGuidanceEnabled=value;
  final prefs=await SharedPreferences.getInstance();await prefs.setBool('voice',value);
 }
 Future<void> _saveTextScale(double value)async{
  setState(()=>textScale=value);appTextScale.value=value;
  final prefs=await SharedPreferences.getInstance();await prefs.setDouble('text_scale',value);
 }
 @override Widget build(BuildContext c)=>Scaffold(
  appBar:AppBar(title:const Text('Accessibility & settings')),
  body:ListView(padding:const EdgeInsets.all(20),children:[
   const Text('Set Saathi up for you',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:navy)),
   const SizedBox(height:8),const Text('These controls work on this phone and are saved automatically.'),
   const SizedBox(height:24),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Spoken safety guidance',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:const Text('Speak warnings and important status messages'),value:voice,onChanged:_saveVoice),
   const SizedBox(height:22),
   const Text('Text size',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:navy)),
   const SizedBox(height:4),const Text('Make labels and instructions easier to read. Android display and TalkBack settings also continue to work.'),
   Slider(value:textScale,min:1.0,max:1.6,divisions:6,label:'${(textScale*100).round()}%',onChanged:_saveTextScale),
   Center(child:Text('${(textScale*100).round()}% text size',style:TextStyle(fontSize:16*textScale,fontWeight:FontWeight.w800,color:navy))),
   const SizedBox(height:22),OutlinedButton.icon(onPressed:()=>stick.announce('Saathi voice test. If you can hear this message, spoken safety guidance is working.'),icon:const Icon(Icons.volume_up_outlined),label:const Text('Test spoken guidance')),
   const SizedBox(height:12),OutlinedButton.icon(onPressed:()=>FirebaseAuth.instance.signOut(),icon:const Icon(Icons.logout),label:const Text('Sign out')),
   const SizedBox(height:24),const Text('Bluetooth connection',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),
   const SizedBox(height:8),const Text('The stick must advertise the Saathi BLE service. If it is not found, check that it is powered on and has the matching firmware. Camera AI and obstacle measurements are shown only when the hardware sends real results.'),
   const SizedBox(height:20),const Text('Safety note',style:TextStyle(color:Color(0xFF64748B))),
   const Text('Saathi is a companion prototype, not a certified mobility aid. Keep using your usual mobility skills and emergency arrangements. The app cannot guarantee GPS accuracy, network availability or emergency delivery.',style:TextStyle(color:Color(0xFF64748B))),
  ]));
}
