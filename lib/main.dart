import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // Asegúrate de que este archivo exista

// Variable global para el tema dinámico
ValueNotifier<Color> globalThemeColor = ValueNotifier(Colors.indigo);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FlashChatApp());
}

class FlashChatApp extends StatelessWidget {
  const FlashChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: globalThemeColor,
      builder: (context, color, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FlashChat Ultimate',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light),
            appBarTheme: AppBarTheme(
              backgroundColor: color, 
              foregroundColor: Colors.white,
              elevation: 2,
              centerTitle: true,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// --- GESTOR DE IDENTIDAD ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<void> _syncUser(User user) async {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await userDoc.get();

    // Si el usuario no existe, lo creamos con datos de Google.
    // Si ya existe, NO sobrescribimos nombre/foto para respetar sus cambios en Configuración.
    if (!snap.exists) {
      await userDoc.set({
        'uid': user.uid,
        'name': user.displayName, // Nombre inicial de Google
        'email': user.email,
        'photoUrl': user.photoURL, // Foto inicial de Google
        'themeColor': Colors.indigo.value,
        'searchKeywords': _generateKeywords(user.displayName ?? ""), // Para búsquedas
      });
    } else {
      // Cargamos su color personalizado
      if (snap.data()?['themeColor'] != null) {
        globalThemeColor.value = Color(snap.data()!['themeColor']);
      }
    }
  }

  // Ayudante para búsquedas (crea array de prefijos: "P", "Pa", "Pab"...)
  List<String> _generateKeywords(String name) {
    List<String> keywords = [];
    String temp = "";
    for (int i = 0; i < name.length; i++) {
      temp = temp + name[i].toLowerCase();
      keywords.add(temp);
    }
    return keywords;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _syncUser(snapshot.data!);
          return const ChatListScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// --- LOGIN ---
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            begin: Alignment.topLeft, end: Alignment.bottomRight
          )
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 100, color: Colors.yellowAccent),
              const SizedBox(height: 10),
              const Text("FLASHCHAT", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text("ENTRAR CON GOOGLE"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () => FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- LISTA DE CHATS CON BUSCADOR ---
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = "";

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("FlashChat"),
          bottom: const TabBar(tabs: [Tab(text: "CHATS"), Tab(text: "PENDIENTES")], indicatorColor: Colors.white, labelColor: Colors.white),
        ),
        drawer: const AppDrawer(),
        floatingActionButton: FloatingActionButton(
          backgroundColor: globalThemeColor.value,
          child: const Icon(Icons.person_add, color: Colors.white),
          onPressed: () => _showAddDialog(context),
        ),
        body: Column(
          children: [
            // BARRA DE BÚSQUEDA DE CHATS
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _filter = val.toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: "Filtrar chats...",
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildList(myUid, false), // Todos
                  _buildList(myUid, true),  // Solo pendientes
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(String? myUid, bool onlyUnread) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: myUid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        var docs = snapshot.data!.docs;

        // Widget especial para el Chat Global (siempre arriba en la lista principal)
        if (!onlyUnread && _filter.isEmpty) {
          // Solo lo mostramos si no estamos filtrando
        }

        return ListView(
          children: [
            if (!onlyUnread && _filter.isEmpty)
              ListTile(
                leading: CircleAvatar(backgroundColor: Colors.orange.shade800, child: const Icon(Icons.public, color: Colors.white)),
                title: const Text("Chat Global", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Comunidad FlashChat"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen(chatId: 'global', title: 'Chat Global'))),
              ),
            
            // Lista dinámica de chats privados
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              String otherUid = (data['participants'] as List).firstWhere((id) => id != myUid, orElse: () => "");

              // Obtenemos datos REALES del usuario (nombre/foto actualizados)
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherUid).get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) return const SizedBox();
                  final userData = userSnap.data!.data() as Map<String, dynamic>;
                  final name = userData['name'] ?? "Usuario";
                  
                  // FILTRO DE BÚSQUEDA LOCAL
                  if (_filter.isNotEmpty && !name.toLowerCase().contains(_filter)) {
                    return const SizedBox();
                  }

                  // Si es pestaña "Pendientes", verificamos si hay mensajes sin leer (simplificado)
                  // (Para una app real, guardaríamos 'unreadCount' en el documento del chat para no leer todos los mensajes)
                  
                  return ListTile(
                    leading: CircleAvatar(backgroundImage: NetworkImage(userData['photoUrl'] ?? "")),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text("Toca para abrir", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: doc.id, title: name))),
                  );
                },
              );
            }).toList(),
          ],
        );
      },
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nuevo Chat"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Busca por nombre (ej: 'Pablo')"),
            const SizedBox(height: 10),
            TextField(controller: controller, decoration: const InputDecoration(hintText: "Nombre del usuario")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if(controller.text.isEmpty) return;
              final query = controller.text.trim().toLowerCase();
              
              // Búsqueda inteligente por keywords (generadas al registrarse/editar)
              // O simplificada: buscar users donde 'name' sea >= query.
              final result = await FirebaseFirestore.instance.collection('users')
                  .where('name', isGreaterThanOrEqualTo: controller.text.trim()) // Case sensitive básica
                  .get();

              if (result.docs.isEmpty) {
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No encontrado. Respeta las mayúsculas.")));
                return;
              }
              
              final target = result.docs.first;
              final me = FirebaseAuth.instance.currentUser!;
              
              if (target.id == me.uid) return;

              List<String> p = [me.uid, target.id];
              p.sort();
              String chatId = p.join("_");
              await FirebaseFirestore.instance.collection('chats').doc(chatId).set({'participants': p}, SetOptions(merge: true));
              
              if(mounted) {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, title: target['name'])));
              }
            },
            child: const Text("Abrir Chat"),
          )
        ],
      ),
    );
  }
}

// --- DRAWER & CONFIGURACIÓN ---
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Usamos StreamBuilder para ver cambios de perfil en tiempo real en el Drawer
    return Drawer(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          var userData = snapshot.data?.data() as Map<String, dynamic>?;
          String displayName = userData?['name'] ?? user?.displayName ?? "Usuario";
          String photoUrl = userData?['photoUrl'] ?? user?.photoURL ?? "";

          return Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                accountEmail: Text(user?.email ?? ""),
                currentAccountPicture: CircleAvatar(backgroundImage: NetworkImage(photoUrl)),
                decoration: BoxDecoration(color: globalThemeColor.value),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text("Configuración de Usuario"),
                subtitle: const Text("Color, nombre, foto..."),
                onTap: () {
                  Navigator.pop(context); // Cerrar drawer
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Cerrar Sesión"),
                onTap: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- PANTALLA DE CONFIGURACIÓN ---
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if(doc.exists) {
      _nameCtrl.text = doc.data()?['name'] ?? "";
      _photoCtrl.text = doc.data()?['photoUrl'] ?? "";
    }
  }

  void _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'name': _nameCtrl.text.trim(),
      'photoUrl': _photoCtrl.text.trim(),
    });
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil actualizado")));
      Navigator.pop(context);
    }
  }

  void _changeColor(Color c) {
    globalThemeColor.value = c;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseFirestore.instance.collection('users').doc(uid).update({'themeColor': c.value});
  }

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.indigo, Colors.blue, Colors.teal, Colors.green, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink, Colors.purple, Colors.blueGrey, Colors.black];

    return Scaffold(
      appBar: AppBar(title: const Text("Configuración")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Editar Perfil", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Nombre visible", prefixIcon: Icon(Icons.person))),
          const SizedBox(height: 15),
          TextField(controller: _photoCtrl, decoration: const InputDecoration(labelText: "URL de tu Foto", prefixIcon: Icon(Icons.link))),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _photoCtrl.text = FirebaseAuth.instance.currentUser?.photoURL ?? "", child: const Text("Restaurar foto Google"))),
          const SizedBox(height: 30),
          
          const Text("Tema de la App", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15, runSpacing: 15,
            children: colors.map((c) => GestureDetector(
              onTap: () => _changeColor(c),
              child: CircleAvatar(backgroundColor: c, radius: 25, child: globalThemeColor.value == c ? const Icon(Icons.check, color: Colors.white) : null),
            )).toList(),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: globalThemeColor.value, foregroundColor: Colors.white),
              onPressed: _save, 
              child: const Text("GUARDAR CAMBIOS")
            ),
          )
        ],
      ),
    );
  }
}

// --- PANTALLA DE CHAT (INTERACTIVA) ---
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  const ChatScreen({super.key, required this.chatId, required this.title});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    // Listener para marcar como leídos
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages')
        .where('senderUid', isNotEqualTo: myUid).where('read', isEqualTo: false)
        .snapshots().listen((event) {
          for (var doc in event.docs) doc.reference.update({'read': true});
        });
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'text': _controller.text.trim(),
      'senderUid': user?.uid,
      'senderName': user?.displayName, // Nota: Se guardará el nombre que tenía AL ENVIAR.
      'senderPhoto': user?.photoURL,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _controller.clear();
    // Auto-scroll al fondo
    Future.delayed(const Duration(milliseconds: 100), () {
      if(_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _handleMessageTap(BuildContext context, Map<String, dynamic> data, String msgId, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text("Responder"),
              onTap: () {
                Navigator.pop(ctx);
                _controller.text = "@${data['senderName']} ";
              },
            ),
            // Opción privada (si no soy yo y es Chat Global)
            if (!isMe && widget.chatId == 'global')
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text("Enviar Mensaje Privado"),
                onTap: () {
                  Navigator.pop(ctx);
                  _createPrivateChat(data['senderUid'], data['senderName']);
                },
              ),
            // Opción borrar (solo si es mío)
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Borrar Mensaje", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(msgId).delete();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _createPrivateChat(String otherUid, String otherName) async {
    final me = FirebaseAuth.instance.currentUser!;
    List<String> p = [me.uid, otherUid];
    p.sort();
    String newId = p.join("_");
    await FirebaseFirestore.instance.collection('chats').doc(newId).set({'participants': p}, SetOptions(merge: true));
    if(mounted) {
      Navigator.pop(context); // Salir del global
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: newId, title: otherName)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId)
                  .collection('messages').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, i) {
                    final doc = snapshot.data!.docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    bool isMe = data['senderUid'] == FirebaseAuth.instance.currentUser?.uid;
                    
                    return GestureDetector(
                      onTap: () => _handleMessageTap(context, data, doc.id, isMe), // CLIC NORMAL ABRE MENÚ
                      child: _bubble(data, isMe),
                    );
                  },
                );
              },
            ),
          ),
          _inputArea(),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> data, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) CircleAvatar(radius: 16, backgroundImage: NetworkImage(data['senderPhoto'] ?? "")),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? globalThemeColor.value : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) Text(data['senderName'] ?? "Usuario", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: globalThemeColor.value)),
                  Text(data['text'] ?? "", style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16)),
                  if (isMe) Align(alignment: Alignment.bottomRight, child: Icon(Icons.done_all, size: 14, color: data['read'] == true ? Colors.blueAccent : Colors.white54))
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _inputArea() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: "Escribe un mensaje...", contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(width: 10),
            FloatingActionButton(
              mini: true,
              backgroundColor: globalThemeColor.value,
              onPressed: _send,
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}