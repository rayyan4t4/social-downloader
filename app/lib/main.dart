import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDefaultBase = 'https://social-downloader-api-seven.vercel.app';

const strings = {
  'en': {
    'pasteHint': 'Paste a TikTok, Instagram, YouTube, Facebook or X link',
    'paste': 'Paste',
    'getInfo': 'Get Video',
    'download': 'Download',
    'history': 'History',
    'home': 'Home',
    'clear': 'Clear',
    'emptyHistory': 'No downloads yet',
    'downloading': 'Downloading…',
    'saved': 'Saved',
    'share': 'Share',
    'settings': 'Settings',
    'backendUrl': 'Backend URL',
    'save': 'Save',
    'language': 'Roman Urdu',
    'setBackend': 'Set your backend URL in Settings first',
    'working': 'Working…',
  },
  'ur': {
    'pasteHint': 'TikTok, Instagram, YouTube, Facebook ya X ka link paste karein',
    'paste': 'Paste',
    'getInfo': 'Video Nikalein',
    'download': 'Download',
    'history': 'History',
    'home': 'Home',
    'clear': 'Saaf karein',
    'emptyHistory': 'Abhi tak koi download nahi',
    'downloading': 'Download ho raha hai…',
    'saved': 'Save ho gaya',
    'share': 'Share',
    'settings': 'Settings',
    'backendUrl': 'Backend URL',
    'save': 'Save',
    'language': 'English',
    'setBackend': 'Pehle Settings mein apna backend URL set karein',
    'working': 'Kaam ho raha hai…',
  },
};

String detectPlatform(String url) {
  final u = url.toLowerCase();
  if (u.contains('tiktok')) return 'TikTok';
  if (u.contains('instagram')) return 'Instagram';
  if (u.contains('youtube') || u.contains('youtu.be')) return 'YouTube';
  if (u.contains('facebook') || u.contains('fb.watch')) return 'Facebook';
  if (u.contains('twitter') || u.contains('x.com')) return 'X';
  return '';
}

String fmtDuration(dynamic sec) {
  if (sec == null) return '';
  final s = (sec as num).toInt();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Social Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Root(),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int tab = 0;
  String lang = 'en';
  String base = kDefaultBase;

  Map<String, String> get t => strings[lang]!;

  @override
  void initState() {
    super.initState();
    loadPrefs();
  }

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      lang = p.getString('lang') ?? 'en';
      base = p.getString('api_base') ?? kDefaultBase;
    });
  }

  Future<void> openSettings() async {
    final ctrl = TextEditingController(text: base);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t['settings']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(labelText: t['backendUrl']),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, lang == 'en' ? 'ur' : 'en'),
              child: Text(t['language']!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, lang),
            child: Text(t['save']!),
          ),
        ],
      ),
    );
    if (result == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('api_base', ctrl.text.trim());
    await p.setString('lang', result);
    setState(() {
      base = ctrl.text.trim();
      lang = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Social Downloader'),
        actions: [
          IconButton(onPressed: openSettings, icon: const Icon(Icons.settings)),
        ],
      ),
      body: tab == 0 ? HomePage(base: base, t: t) : HistoryPage(t: t),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.download), label: t['home']!),
          NavigationDestination(icon: const Icon(Icons.history), label: t['history']!),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String base;
  final Map<String, String> t;
  const HomePage({super.key, required this.base, required this.t});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final urlCtrl = TextEditingController();
  Map<String, dynamic>? info;
  String mode = 'hd';
  bool busy = false;
  double progress = 0;
  String? lastFile;

  String get base => widget.base;
  Map<String, String> get t => widget.t;

  void showMsg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => urlCtrl.text = d!.text!.trim());
  }

  Future<void> resolve() async {
    if (base == kDefaultBase) return showMsg(t['setBackend']!);
    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      busy = true;
      info = null;
      lastFile = null;
    });
    try {
      final r = await http.post(
        Uri.parse('$base/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );
      final body = jsonDecode(r.body);
      if (r.statusCode != 200) {
        showMsg(body['detail']?.toString() ?? 'Error ${r.statusCode}');
      } else {
        setState(() => info = body as Map<String, dynamic>);
      }
    } catch (e) {
      showMsg(e.toString());
    }
    setState(() => busy = false);
  }

  Future<void> download() async {
    if (base == kDefaultBase) return showMsg(t['setBackend']!);
    final url = urlCtrl.text.trim();
    setState(() {
      busy = true;
      progress = 0;
      lastFile = null;
    });
    try {
      final req = http.Request(
        'GET',
        Uri.parse('$base/fetch').replace(
          queryParameters: {'url': url, 'mode': mode},
        ),
      );
      final res = await http.Client().send(req);
      if (res.statusCode != 200) {
        final b = await res.stream.bytesToString();
        String msg = 'Error ${res.statusCode}';
        try {
          msg = jsonDecode(b)['detail']?.toString() ?? msg;
        } catch (_) {}
        showMsg(msg);
        setState(() => busy = false);
        return;
      }
      final total = res.contentLength ?? 0;
      var ext = mode == 'mp3' ? 'mp3' : 'mp4';
      final cd = res.headers['content-disposition'] ?? '';
      final m = RegExp(r'filename="[^"]*\.(\w+)"').firstMatch(cd);
      if (m != null) ext = m.group(1)!;
      final name = 'dl_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final dir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/downloads');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) setState(() => progress = received / total);
      }
      await sink.close();
      final p = await SharedPreferences.getInstance();
      final hist = p.getStringList('history') ?? [];
      hist.insert(
        0,
        jsonEncode({
          'title': info?['title'] ?? name,
          'platform': info?['platform'] ?? detectPlatform(url),
          'url': url,
          'mode': mode,
          'path': file.path,
          'date': DateTime.now().toIso8601String(),
        }),
      );
      await p.setStringList('history', hist);
      setState(() => lastFile = file.path);
      showMsg('${t['saved']}: ${file.path}');
    } catch (e) {
      showMsg(e.toString());
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final platform = detectPlatform(urlCtrl.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: urlCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t['pasteHint'],
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: paste,
                icon: const Icon(Icons.content_paste),
                tooltip: t['paste'],
              ),
            ),
          ),
          if (platform.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text(platform)),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : resolve,
            child: Text(busy && info == null ? t['working']! : t['getInfo']!),
          ),
          if (info != null) ...[
            const SizedBox(height: 16),
            if (info!['thumbnail'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  info!['thumbnail'],
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              info!['title']?.toString() ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${info!['platform'] ?? ''}  ${fmtDuration(info!['duration'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'hd', label: Text('HD')),
                ButtonSegment(value: 'sd', label: Text('SD')),
                ButtonSegment(value: 'mp3', label: Text('MP3')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => mode = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : download,
              icon: const Icon(Icons.download),
              label: Text(t['download']!),
            ),
          ],
          if (busy && info != null) ...[
            const SizedBox(height: 16),
            Text(t['downloading']!),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
          ],
          if (lastFile != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Share.shareXFiles([XFile(lastFile!)], text: info?['title']),
              icon: const Icon(Icons.share),
              label: Text(t['share']!),
            ),
          ],
        ],
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  final Map<String, String> t;
  const HistoryPage({super.key, required this.t});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('history') ?? [];
    setState(() {
      items = raw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    });
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('history');
    setState(() => items = []);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(widget.t['emptyHistory']!));
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: clear,
            child: Text(widget.t['clear']!),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final it = items[i];
              final path = it['path']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.video_file),
                title: Text(it['title']?.toString() ?? ''),
                subtitle: Text(
                    '${it['platform'] ?? ''} • ${it['mode'] ?? ''} • ${(it['date'] ?? '').toString().substring(0, 10)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: path.isNotEmpty && File(path).existsSync()
                      ? () => Share.shareXFiles([XFile(path)])
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
