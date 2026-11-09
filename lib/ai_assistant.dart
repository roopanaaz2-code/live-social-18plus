import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

class NightLinkAiScreen extends StatefulWidget {
  const NightLinkAiScreen({super.key});

  @override
  State<NightLinkAiScreen> createState() => _NightLinkAiScreenState();
}

class _NightLinkAiScreenState extends State<NightLinkAiScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;
  bool _speechReady = false;
  bool _listening = false;
  bool _speakReplies = true;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'assistant',
      'content': 'Welcome to NightLink AI ✨\nAsk me about NightLink, technology, learning, creativity or everyday questions. You can type or tap the microphone to speak.',
    });
    _initVoice();
  }

  Future<void> _initVoice() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status == 'listening');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _voiceError = error.errorMsg;
          });
        },
      );
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _voiceError = error.toString());
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      await _initVoice();
      if (!_speechReady) {
        if (mounted) setState(() => _voiceError = 'Speech recognition is unavailable. Check microphone permission and your device speech service.');
        return;
      }
    }
    setState(() => _voiceError = null);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _input.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      partialResults: true,
      cancelOnError: true,
    );
    if (mounted) setState(() => _listening = true);
  }

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _sending) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _messages.add({'role': 'user', 'content': prompt});
      _sending = true;
      _voiceError = null;
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((message) => message['role'] == 'user' || message['role'] == 'assistant')
          .toList()
          .reversed
          .take(12)
          .toList()
          .reversed
          .map((message) => {
                'role': message['role'],
                'content': message['content'],
              })
          .toList();

      final response = await Supabase.instance.client.functions.invoke(
        'nightlink-ai-chat',
        body: {'messages': history},
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        final detail = data is Map ? data['error']?.toString() : null;
        throw Exception(detail ?? 'NightLink AI could not answer (HTTP ${response.status}).');
      }
      final reply = data['reply']?.toString().trim();
      if (reply == null || reply.isEmpty) {
        throw Exception('The AI service returned an empty reply. Please try again.');
      }
      if (!mounted) return;
      setState(() => _messages.add({'role': 'assistant', 'content': reply}));
      _scrollToBottom();
      if (_speakReplies) {
        try {
          await _tts.stop();
          await _tts.speak(reply);
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted) return;
      final detail = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': 'I could not reach the AI service just now. $detail',
        });
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _dark,
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B35),
          title: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _gold.withOpacity(.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.auto_awesome, color: _gold),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NIGHTLINK AI', style: TextStyle(color: _gold, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Your smart companion', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ]),
          actions: [
            IconButton(
              tooltip: _speakReplies ? 'Turn voice replies off' : 'Turn voice replies on',
              onPressed: () => setState(() => _speakReplies = !_speakReplies),
              icon: Icon(_speakReplies ? Icons.volume_up : Icons.volume_off, color: _blue),
            ),
          ],
        ),
        body: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF172B4D), Color(0xFF11182B)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _blue.withOpacity(.25)),
            ),
            child: const Row(children: [
              Icon(Icons.bolt, color: _gold, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Ask anything • English • اردو • پښتو • Voice input', style: TextStyle(color: Colors.white70, fontSize: 12))),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_sending && index == _messages.length) {
                  return const _TypingBubble();
                }
                final message = _messages[index];
                final mine = message['role'] == 'user';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: mine
                          ? const LinearGradient(colors: [Color(0xFF214B7D), Color(0xFF17365D)])
                          : const LinearGradient(colors: [Color(0xFF202B40), Color(0xFF151E31)]),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(mine ? 18 : 5),
                        bottomRight: Radius.circular(mine ? 5 : 18),
                      ),
                      border: Border.all(color: mine ? _blue.withOpacity(.3) : Colors.white10),
                    ),
                    child: Text(message['content'] ?? '', style: const TextStyle(color: Colors.white, height: 1.45)),
                  ),
                );
              },
            ),
          ),
          if (_voiceError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_voiceError!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  decoration: BoxDecoration(
                    color: _listening ? Colors.redAccent.withOpacity(.18) : const Color(0xFF17233A),
                    shape: BoxShape.circle,
                    border: Border.all(color: _listening ? Colors.redAccent : _blue.withOpacity(.35)),
                  ),
                  child: IconButton(
                    tooltip: _listening ? 'Stop listening' : 'Speak to NightLink AI',
                    onPressed: _toggleMic,
                    icon: Icon(_listening ? Icons.stop : Icons.mic, color: _listening ? Colors.redAccent : _gold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _listening ? 'Listening…' : 'Message NightLink AI',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF151E31),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                  child: IconButton(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded, color: _dark),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF202B40),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const SizedBox(
            width: 28,
            height: 12,
            child: Center(child: Text('•••', style: TextStyle(color: _gold, letterSpacing: 3))),
          ),
        ),
      );
}
