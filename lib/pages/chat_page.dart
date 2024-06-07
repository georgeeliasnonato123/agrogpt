import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _openAI = OpenAI.instance.build(
    token: dotenv.env['OPEN_IA_API_KEY'] ?? '',
    baseOption: HttpSetup(
      receiveTimeout: const Duration(seconds: 5),
    ),
    enableLog: true,
  );

  final ChatUser _user = ChatUser(
    id: '1',
    firstName: 'Leonardo',
    lastName: 'Freitas',
  );

  final ChatUser _gptChatUser = ChatUser(
    id: '2',
    firstName: 'Chat',
    lastName: 'GPT',
  );

  List<ChatMessage> _messages = <ChatMessage>[];
  final List<ChatUser> _typingUsers = <ChatUser>[];
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _checkUser();
    _loadMessages();
  }

  void _checkUser() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  Future<void> _loadMessages() async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .get();
    final messages = querySnapshot.docs.map((doc) {
      final data = doc.data();
      return ChatMessage(
        text: data['text'],
        user: data['userId'] == _user.id ? _user : _gptChatUser,
        createdAt: data['createdAt'].toDate(),
      );
    }).toList();
    setState(() {
      _messages = messages;
    });
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
    });
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color.fromRGBO(0, 166, 126, 1),
        title: const Text(
          'AgroGPT: Tela de Chat',
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        actions: [
          _loggingOut
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : IconButton(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                ),
        ],
      ),
      body: _loggingOut
          ? Center(
              child: CircularProgressIndicator(),
            )
          : Container(
              color: const Color.fromARGB(255, 59, 58, 58),
              child: DashChat(
                currentUser: _user,
                messageOptions: const MessageOptions(
                  currentUserContainerColor: Colors.grey,
                  containerColor: Color.fromRGBO(0, 166, 126, 1),
                  textColor: Colors.white,
                ),
                onSend: (ChatMessage m) {
                  _sendMessage(m);
                  getChatResponse(m);
                },
                messages: _messages,
                typingUsers: _typingUsers,
              ),
            ),
    );
  }

  Future<void> _sendMessage(ChatMessage m) async {
    await FirebaseFirestore.instance.collection('messages').add({
      'text': m.text,
      'userId': m.user.id,
      'createdAt': m.createdAt,
    });
    setState(() {
      _messages.insert(0, m);
    });
  }

  Future<void> getChatResponse(ChatMessage m) async {
    setState(() {
      _typingUsers.add(_gptChatUser);
    });

    try {
      List<Map<String, dynamic>> messagesHistory =
          _messages.reversed.toList().map((m) {
        if (m.user == _user) {
          return Messages(role: Role.user, content: m.text).toJson();
        } else {
          return Messages(role: Role.assistant, content: m.text).toJson();
        }
      }).toList();
      final request = ChatCompleteText(
        messages: messagesHistory,
        maxToken: 200,
        model: GptTurbo16k0631Model(),
      );
      final response = await _openAI.onChatCompletion(request: request);

      if (response != null) {
        for (var element in response.choices) {
          if (element.message != null) {
            final chatMessage = ChatMessage(
              user: _gptChatUser,
              createdAt: DateTime.now(),
              text: element.message!.content,
            );
            await FirebaseFirestore.instance.collection('messages').add({
              'text': chatMessage.text,
              'userId': chatMessage.user.id,
              'createdAt': chatMessage.createdAt,
            });
            setState(() {
              _messages.insert(0, chatMessage);
            });
          }
        }
      } else {
        throw Exception('Resposta nula da API');
      }
    } catch (e) {
      final errorMessage = ChatMessage(
        user: _gptChatUser,
        createdAt: DateTime.now(),
        text: 'Ocorreu um erro ao processar sua mensagem: $e',
      );
      setState(() {
        _messages.insert(0, errorMessage);
      });
    } finally {
      setState(() {
        _typingUsers.remove(_gptChatUser);
      });
    }
  }
}
