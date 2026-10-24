import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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

class BlindStickApp extends StatelessWidget {
  const BlindStickApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Saathi', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: teal), scaffoldBackgroundColor: const Color(0xFFF7FAFC), fontFamily: 'Roboto',
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE5E9))), contentPadding: const EdgeInsets.all(16))),
    home: const AuthGate());
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
 Text('Signed in as $email. A project administrator must assign your patient or caregiver role and pairing permissions before access is enabled.',textAlign:TextAlign.center,style:const TextStyle(fontSize:16)),const SizedBox(height:22),FilledButton.icon(onPressed:()=>FirebaseAuth.instance.signOut(),icon:const Icon(Icons.logout),label:const Text('Sign out'))
 ])))));
}

class LoginPage extends StatefulWidget { const LoginPage({super.key}); @override State<LoginPage> createState()=>_LoginPageState(); }
class _LoginPageState extends State<LoginPage> {
 final email=TextEditingController(),password=TextEditingController(),name=TextEditingController();bool hide=true,createAccount=false,busy=false;String? error,info;
 @override void dispose(){email.dispose();password.dispose();name.dispose();super.dispose();}
 Future<void> submit() async {
  if(busy)return;
  if(email.text.trim().isEmpty||!email.text.contains('@')||password.text.length<6||(createAccount&&name.text.trim().isEmpty)){setState(()=>error=createAccount?'Enter your name, a valid email and a password of at least 6 characters.':'Enter your email and password (at least 6 characters).');return;}
  setState(()=>{busy=true,error=null,info=null});
  try{
   if(createAccount){
    final credential=await FirebaseAuth.instance.createUserWithEmailAndPassword(email:email.text.trim(),password:password.text);
    await credential.user!.updateDisplayName(name.text.trim());
    await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({'uid':credential.user!.uid,'email':email.text.trim().toLowerCase(),'displayName':name.text.trim(),'role':'pending','createdAt':FieldValue.serverTimestamp()});
    if(mounted)setState(()=>info='Account created. An administrator must assign your role and pairing permissions before use.');
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
 @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
 const SizedBox(height:16),Container(width:68,height:68,alignment:Alignment.center,decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(22)),child:const Icon(Icons.accessibility_new_rounded,color:Colors.white,size:42)),
 const SizedBox(height:20),const Text('Saathi',style:TextStyle(fontSize:38,fontWeight:FontWeight.w900,color:navy)),const Text('Your companion for safer journeys',style:TextStyle(fontSize:17,color:Color(0xFF59697B))),const SizedBox(height:32),
 Text(createAccount?'Create your account':'Welcome back',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:16),
 if(createAccount)...[TextField(controller:name,textCapitalization:TextCapitalization.words,autofillHints:const [AutofillHints.name],decoration:const InputDecoration(labelText:'Your name',prefixIcon:Icon(Icons.person_outline))),const SizedBox(height:12)],
 TextField(controller:email,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],textInputAction:TextInputAction.next,decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.email_outlined))),const SizedBox(height:12),
 TextField(controller:password,obscureText:hide,autofillHints:createAccount?const [AutofillHints.newPassword]:const [AutofillHints.password],onSubmitted:(_)=>submit(),decoration:InputDecoration(labelText:'Password',helperText:createAccount?'Use at least 6 characters':'',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>hide=!hide),icon:Icon(hide?Icons.visibility:Icons.visibility_off)))),
 if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:red))),if(info!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(info!,style:const TextStyle(color:teal))),
 const SizedBox(height:20),SizedBox(height:58,child:FilledButton.icon(onPressed:busy?null:submit,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Icon(createAccount?Icons.person_add_alt_1:Icons.arrow_forward),label:Text(busy?'Please wait…':createAccount?'Create account':'Sign in',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))),
 if(!createAccount)Align(alignment:Alignment.centerRight,child:TextButton(onPressed:busy?null:resetPassword,child:const Text('Forgot password?'))),
 TextButton(onPressed:busy?null:()=>setState(()=>{createAccount=!createAccount,error=null,info=null}),child:Text(createAccount?'Already have an account? Sign in':'New here? Create an account')),
 const SizedBox(height:20),const Text('A project administrator must assign patient/caregiver roles and authorize pairing before an account can access personal data or control a stick.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF64748B),fontSize:13))
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
 static final ApiService instance=ApiService._(); ApiService._(); String baseUrl=''; String token='';
 Map<String,String> get headers=>{'Content-Type':'application/json',if(token.isNotEmpty)'Authorization':'Bearer $token'};
 Uri? uri(String path){if(baseUrl.trim().isEmpty)return null; final b=baseUrl.trim().replaceAll(RegExp(r'/$'),''); return Uri.tryParse('$b$path');}
 Future<bool> send(String path,Map<String,dynamic> body)async{final u=uri(path);if(u==null)return false;try{final r=await http.post(u,headers:headers,body:jsonEncode(body)).timeout(const Duration(seconds:8));return r.statusCode>=200&&r.statusCode<300;}catch(_){return false;}}
 Future<Map<String,dynamic>?> getJson(String path)async{final u=uri(path);if(u==null)return null;try{final r=await http.get(u,headers:headers).timeout(const Duration(seconds:8));if(r.statusCode<200||r.statusCode>=300)return null;final d=jsonDecode(r.body);return d is Map<String,dynamic>?d:null;}catch(_){return null;}}
 Future<bool> getOk(String path)async=>await getJson(path)!=null;
 Future<bool> sos(String patient,Position? pos,String detail)=>send('/api/sos',{'patient_id':patient,'message':detail,'latitude':pos?.latitude,'longitude':pos?.longitude,'created_at':DateTime.now().toUtc().toIso8601String()});
 Future<bool> location(String patient,Position pos)=>send('/api/locations',{'patient_id':patient,'latitude':pos.latitude,'longitude':pos.longitude,'accuracy_m':pos.accuracy,'recorded_at':DateTime.now().toUtc().toIso8601String()});
 Future<bool> event(String patient,String kind,String detail)=>send('/api/events',{'patient_id':patient,'type':kind,'detail':detail,'created_at':DateTime.now().toUtc().toIso8601String()});
 Future<bool> caregiverStatus(String patient)=>getOk('/api/patients/${Uri.encodeComponent(patient)}/status');
}

class BleStickService extends ChangeNotifier {
 final FlutterTts tts=FlutterTts(); final StickTelemetry telemetry=StickTelemetry(); BluetoothDevice? device; BluetoothCharacteristic? telemetryChar, commandChar; StreamSubscription<List<ScanResult>>? scanSub; StreamSubscription<List<int>>? notifySub; StreamSubscription<BluetoothConnectionState>? connectionSub; StreamSubscription<BluetoothAdapterState>? adapterSub;
 bool scanning=false,connected=false,assistance=false; String status='Stick not connected'; String? lastError; final List<String> events=[]; DateTime? lastSpoken; String _lastWarning='';
 BleStickService(){tts.setLanguage('en-IN');tts.setSpeechRate(0.46);}
 Future<void> scanAndConnect() async {
  if(scanning)return; scanning=true;status='Looking for your stick';lastError=null;notifyListeners();
  try{
   final scanPermission=await Permission.bluetoothScan.request();
   final connectPermission=await Permission.bluetoothConnect.request();
   if(!scanPermission.isGranted||!connectPermission.isGranted){status='Bluetooth permission needed';lastError='Allow Bluetooth access in Android settings to find the stick.';return;}
   final state=await FlutterBluePlus.adapterState.first; if(state!=BluetoothAdapterState.on){status='Please turn Bluetooth on';lastError='Bluetooth is off';scanning=false;notifyListeners();return;}
   await FlutterBluePlus.startScan(timeout:const Duration(seconds:12),withServices:[Guid(serviceUuid)]);
   final results=await FlutterBluePlus.scanResults.firstWhere((r)=>r.any((x)=>x.advertisementData.serviceUuids.any((g)=>g==Guid(serviceUuid)))).timeout(const Duration(seconds:12),onTimeout:()=>FlutterBluePlus.scanResults.first);
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
 void _handlePacket(List<int> bytes){try{final raw=utf8.decode(bytes,allowMalformed:true).trim();for(final line in raw.split(RegExp(r'[\r\n]+'))){if(line.isEmpty)continue;final decoded=jsonDecode(line);if(decoded is Map<String,dynamic>){telemetry.fromJson(decoded);_processSafety();}}}catch(e){lastError='Unreadable data received from stick. Check the firmware packet format.';}notifyListeners();}
 void _processSafety(){final t=telemetry;String warning='';if(t.distanceCm!=null){if(t.distanceCm!<35)warning='Stop. Obstacle very close.';else if(t.distanceCm!<90)warning='Caution. Obstacle ahead.';}if(t.object.toLowerCase().contains('traffic')&&t.trafficWalk==false)warning='Stop. Do not cross yet.';if(t.crowd.toLowerCase()=='high')warning='Crowded area ahead. Slow down.';if(warning.isNotEmpty&&warning!=_lastWarning){_lastWarning=warning;_event(warning);HapticFeedback.heavyImpact();_speak(warning);}if(warning.isEmpty)_lastWarning='';}
 Future<void> _command(Map<String,dynamic> cmd)async{if(!connected||commandChar==null)return;final bytes=utf8.encode('${jsonEncode(cmd)}\n');await commandChar!.write(bytes,withoutResponse:commandChar!.properties.writeWithoutResponse&&!commandChar!.properties.write);}
 Future<void> setAssistance(bool on)async{assistance=on;await _command({'cmd':on?'start':'stop'});_event(on?'Assistance started':'Assistance paused');if(on)_speak('Assistance started. Stay aware of your surroundings.');notifyListeners();}
 Future<void> _speak(String s)async{if(!voiceGuidanceEnabled)return;await tts.stop();await tts.speak(s);}
 Future<void> announce(String s)=>_speak(s);
 void _event(String s){final now=DateTime.now();final stamp='${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';events.insert(0,'$stamp · $s');if(events.length>50)events.removeLast();}
 Future<void> disconnect()async{await device?.disconnect();connected=false;assistance=false;status='Stick disconnected';notifyListeners();}
 @override void dispose(){scanSub?.cancel();notifySub?.cancel();connectionSub?.cancel();adapterSub?.cancel();device?.disconnect();tts.stop();super.dispose();}
}
final stick=BleStickService();

Future<Position?> getPosition()async{try{if(!await Geolocator.isLocationServiceEnabled())return null;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)return null;return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:15)));}catch(_){return null;}}
Future<void> openNavigation(BuildContext context,String destination) async {
  void showMessage(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  if (destination.trim().isEmpty) {
    showMessage('Please enter a destination first.');
    return;
  }
  final pos = await getPosition();
  if (!context.mounted) return;
  if (pos == null) {
    showMessage('Location unavailable. Enable location permission and GPS, then try again.');
    return;
  }
  final q = Uri.encodeComponent(destination.trim());
  final route = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=${pos.latitude},${pos.longitude}&destination=$q&travelmode=walking&dir_action=navigate');
  try {
    final opened = await launchUrl(route, mode: LaunchMode.externalApplication);
    if (!opened) showMessage('Could not open navigation. Install or enable a maps app.');
  } catch (_) {
    showMessage('Could not open navigation. Check your internet connection and maps app.');
  }
}

class PatientPage extends StatefulWidget{final AppUser user;const PatientPage({super.key,required this.user});@override State<PatientPage> createState()=>_PatientPageState();}
class _PatientPageState extends State<PatientPage>{final destination=TextEditingController();final api=ApiService.instance;Position? position;bool sharing=false,voice=true;Timer? locationTimer;String locationText='Location not checked yet';
 @override void initState(){super.initState();_load();stick.addListener(_changed);}
 Future<void> _load()async{final p=await SharedPreferences.getInstance();if(!mounted)return;setState(()=>voice=p.getBool('voice')??true);voiceGuidanceEnabled=voice;_refreshLocation();}
 void _changed(){if(!mounted)return;setState((){});}
 Future<void> _refreshLocation()async{final p=await getPosition();if(!mounted)return;setState(() { position=p; locationText=p==null?'Location unavailable':'Location ready · accuracy ${p.accuracy.round()} m'; });if(sharing&&p!=null)await api.location(widget.user.username,p);}
 Future<void> _toggleSharing(bool v)async{setState(()=>sharing=v);locationTimer?.cancel();if(v){await _refreshLocation();locationTimer=Timer.periodic(const Duration(seconds:30),(_)=>_refreshLocation());}else{setState(()=>locationText='Location sharing paused');}}
 Future<void> _sos()async{final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Send emergency alert?'),content:const Text('This will attempt to send your location and SOS message to the configured backend. If the backend is not configured or the network is unavailable, no caregiver will be notified.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Send SOS'))]));if(ok!=true)return;final p=position??await getPosition();final sent=await api.sos(widget.user.username,p,'Patient requested emergency assistance');await api.event(widget.user.username,'sos',sent?'SOS submitted to backend':'SOS attempt failed — backend unavailable');if(!mounted)return;await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(sent?'SOS submitted':'SOS not delivered'),content:Text(sent?'The backend accepted the alert. Please also use your usual emergency contact method if you are in danger.':'No alert was delivered. Configure the backend and internet, or call your emergency contact directly.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('OK'))]));}
 @override void dispose(){destination.dispose();locationTimer?.cancel();stick.removeListener(_changed);super.dispose();}
 @override Widget build(BuildContext c){final t=stick.telemetry;return Scaffold(appBar:AppBar(title:const Text('Saathi · My journey',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(tooltip:'Settings',onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SettingsPage())),icon:const Icon(Icons.settings_outlined))]),body:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,28),children:[
  Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Hello, ${widget.user.name}',style:const TextStyle(color:Colors.white70,fontSize:16)),const SizedBox(height:6),const Text('Ready when you are.',style:TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:14),Row(children:[Icon(stick.connected?Icons.bluetooth_connected:Icons.bluetooth_disabled,color:stick.connected?const Color(0xFF9FF0D0):Colors.orangeAccent),const SizedBox(width:8),Expanded(child:Text(stick.status,style:const TextStyle(color:Colors.white,fontSize:14)))])])),const SizedBox(height:16),
  Row(children:[Expanded(child:_statusTile('Obstacle range',t.distanceCm==null?'Waiting': '${t.distanceCm!.round()} cm',t.urgent?red:t.caution?Colors.orange:teal,Icons.radar)),const SizedBox(width:10),Expanded(child:_statusTile('Camera',t.receivedAt==null?'No data':t.object,teal,Icons.camera_alt_outlined))]),const SizedBox(height:12),
  if(stick.lastError!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFF1F0),borderRadius:BorderRadius.circular(14)),child:Text(stick.lastError!,style:const TextStyle(color:red))),
  SizedBox(height:56,child:FilledButton.icon(onPressed:stick.scanning?null:stick.scanAndConnect,icon:Icon(stick.scanning?Icons.hourglass_top:Icons.bluetooth_searching),label:Text(stick.scanning?'Searching…':stick.connected?'Reconnect to stick':'Find my stick',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)))),const SizedBox(height:10),
  SizedBox(height:62,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:stick.assistance?red:teal,foregroundColor:Colors.white),onPressed:stick.connected?()=>stick.setAssistance(!stick.assistance):null,icon:Icon(stick.assistance?Icons.pause_circle_filled:Icons.play_circle_fill,size:28),label:Text(stick.assistance?'Pause assistance':'Start assistance',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)))),if(!stick.connected)const Padding(padding:EdgeInsets.only(top:8),child:Text('Connect the physical stick before starting live assistance.',style:TextStyle(color:Color(0xFF64748B)))),const SizedBox(height:22),
  _section('Get somewhere',Icons.navigation_outlined),const SizedBox(height:10),TextField(controller:destination,textInputAction:TextInputAction.go,onSubmitted:(v)=>openNavigation(c,v),decoration:const InputDecoration(labelText:'Where would you like to go?',hintText:'Enter a place or address',prefixIcon:Icon(Icons.place_outlined))),const SizedBox(height:10),SizedBox(height:54,child:FilledButton.icon(onPressed:()=>openNavigation(c,destination.text),icon:const Icon(Icons.directions_walk),label:const Text('Start walking directions',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)))),const SizedBox(height:8),Text(locationText,style:const TextStyle(color:Color(0xFF64748B))),TextButton.icon(onPressed:_refreshLocation,icon:const Icon(Icons.my_location),label:const Text('Check my location')),const SizedBox(height:20),
  _section('Keep your caregiver informed',Icons.favorite_outline),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Share my location',style:TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(sharing?'Attempts an update every 30 seconds when the backend is configured':'Off until you choose to share'),value:sharing,onChanged:_toggleSharing),const SizedBox(height:10),
  SizedBox(height:62,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white),onPressed:_sos,icon:const Icon(Icons.sos,size:30),label:const Text('SOS · Ask for help',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)))),const SizedBox(height:20),
  _section('Recent alerts',Icons.notifications_active_outlined),const SizedBox(height:8),if(stick.events.isEmpty)const Text('Your device events will appear here after connection.')else ...stick.events.take(8).map((e)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.circle,size:10,color:teal),title:Text(e,style:const TextStyle(fontSize:14))))
 ]));}
 Widget _statusTile(String title,String value,Color color,IconData icon)=>Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFE1E8EE))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:25),const SizedBox(height:12),Text(title,style:const TextStyle(color:Color(0xFF68778A))),const SizedBox(height:4),Text(value,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:navy,fontWeight:FontWeight.w900,fontSize:17))]));
 Widget _section(String s,IconData i)=>Row(children:[Icon(i,color:teal),const SizedBox(width:8),Text(s,style:const TextStyle(color:navy,fontSize:19,fontWeight:FontWeight.w900))]);
}

class CaregiverPage extends StatefulWidget{final AppUser user;const CaregiverPage({super.key,required this.user});@override State<CaregiverPage> createState()=>_CaregiverPageState();}
class _CaregiverPageState extends State<CaregiverPage>{final patient=TextEditingController(text:'patient');final api=ApiService.instance;String status='Not checked';bool busy=false;double? patientLat,patientLon;String latestAlert='No alert data received';Timer? timer;
 @override void initState(){super.initState();_check();timer=Timer.periodic(const Duration(seconds:45),(_)=>_check(silent:true));}
 Future<void> _check({bool silent=false})async{if(busy)return;busy=true;final data=await api.getJson('/api/patients/${Uri.encodeComponent(patient.text.trim())}/status');if(!mounted)return;final loc=data?['last_location'];final alerts=data?['recent_alerts'];setState((){status=api.baseUrl.isEmpty?'Backend not configured':data==null?'Could not reach patient status endpoint':'Patient status received';if(loc is Map){final a=loc['latitude'];final b=loc['longitude'];patientLat=a is num?a.toDouble():null;patientLon=b is num?b.toDouble():null;}if(alerts is List&&alerts.isNotEmpty){final a=alerts.first;latestAlert=a is Map?'${a['type']??'Alert'} · ${a['created_at']??''}':a.toString();}});busy=false;if(!silent)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(status)));}
 Future<void> _openLastLocation()async{if(patientLat==null||patientLon==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No patient coordinates have been returned by the backend yet.')));return;}final url=Uri.parse('https://www.google.com/maps/search/?api=1&query=$patientLat,$patientLon');await launchUrl(url,mode:LaunchMode.externalApplication);}
 @override void dispose(){patient.dispose();timer?.cancel();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Saathi · Caregiver',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SettingsPage())),icon:const Icon(Icons.settings_outlined))]),body:ListView(padding:const EdgeInsets.all(20),children:[Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.health_and_safety_outlined,color:Color(0xFF9FF0D0),size:36),SizedBox(height:16),Text('Care from a distance.',style:TextStyle(color:Colors.white,fontSize:27,fontWeight:FontWeight.w900)),SizedBox(height:8),Text('Check connection and backend status for the person you support.',style:TextStyle(color:Colors.white70,fontSize:15))])),const SizedBox(height:22),const Text('Patient account',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:8),TextField(controller:patient,decoration:const InputDecoration(labelText:'Patient username',prefixIcon:Icon(Icons.person_outline))),const SizedBox(height:12),SizedBox(height:54,child:FilledButton.icon(onPressed:()=>_check(),icon:const Icon(Icons.sync),label:const Text('Check patient status'))),const SizedBox(height:12),Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:pale,borderRadius:BorderRadius.circular(16)),child:Text(status,style:const TextStyle(fontWeight:FontWeight.w700))),const SizedBox(height:20),const Text('Latest patient update',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:8),Text('Latest alert: $latestAlert'),const SizedBox(height:8),Text(patientLat==null?'No location received yet':'Last location: ${patientLat!.toStringAsFixed(5)}, ${patientLon!.toStringAsFixed(5)}'),const SizedBox(height:16),const Text('The caregiver dashboard reads the configured backend response. It never invents patient location or alert data.',style:TextStyle(color:Color(0xFF64748B))),const SizedBox(height:16),OutlinedButton.icon(onPressed:_openLastLocation,icon:const Icon(Icons.map_outlined),label:const Text('Open last known location in Maps')),const SizedBox(height:12),const Text('For privacy, only monitor a patient who has consented and has been paired through your backend.',style:TextStyle(color:Color(0xFF64748B))) ]));
}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{final url=TextEditingController();final token=TextEditingController();final tts=FlutterTts();bool voice=true;String saved='';
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{final p=await SharedPreferences.getInstance();if(!mounted)return;url.text=p.getString('api_base_url')??'';token.text=p.getString('api_token')??'';setState(()=>voice=p.getBool('voice')??true);ApiService.instance.baseUrl=url.text;ApiService.instance.token=token.text;}
 Future<void> _save()async{final p=await SharedPreferences.getInstance();await p.setString('api_base_url',url.text.trim());await p.setString('api_token',token.text.trim());await p.setBool('voice',voice);ApiService.instance.baseUrl=url.text.trim();ApiService.instance.token=token.text.trim();setState(()=>saved='Settings saved on this phone.');}
 @override void dispose(){url.dispose();token.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Settings')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Make Saathi yours',style:TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),const Text('These settings work on this phone. Keep the interface simple and adjust it to your needs.'),const SizedBox(height:24),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Voice guidance',style:TextStyle(fontWeight:FontWeight.w700)),subtitle:const Text('Speak device and safety messages'),value:voice,onChanged:(v)async{setState(()=>voice=v);voiceGuidanceEnabled=v;final p=await SharedPreferences.getInstance();await p.setBool('voice',v);}),const SizedBox(height:18),const Text('Backend connection',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),const Text('Enter the base URL of your API. The app expects the endpoints documented in README.md.'),const SizedBox(height:12),TextField(controller:url,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'API base URL',hintText:'https://your-api.example.com',prefixIcon:Icon(Icons.cloud_outlined))),const SizedBox(height:12),TextField(controller:token,obscureText:true,decoration:const InputDecoration(labelText:'Bearer token (optional)',prefixIcon:Icon(Icons.key_outlined))),const SizedBox(height:16),SizedBox(height:54,child:FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save_outlined),label:const Text('Save settings'))),if(saved.isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:Text(saved,style:const TextStyle(color:teal))),const SizedBox(height:22),const Text('Hardware protocol',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:8),const Text('BLE connection uses the Saathi UUIDs and newline-delimited JSON packets listed in the project README. Firmware must advertise the configured service UUID and expose telemetry + command characteristics.'),const SizedBox(height:16),OutlinedButton.icon(onPressed:()=>stick.announce('Saathi voice test. If you can hear this message, voice guidance is working.'),icon:const Icon(Icons.volume_up_outlined),label:const Text('Test voice guidance'))]));
}
