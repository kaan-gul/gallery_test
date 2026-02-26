import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ImageTestApp());
}

class ImageTestApp extends StatelessWidget {
  const ImageTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'iOS Dosya Silinme Testi',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const TestHomePage(),
    );
  }
}

// --- VERİTABANI KATI ---
class TestImageModel {
  final int id;
  final String dbSavedPath;
  final String currentFixedPath;

  TestImageModel({
    required this.id,
    required this.dbSavedPath,
    required this.currentFixedPath,
  });
}

class TestDBHelper {
  static final TestDBHelper instance = TestDBHelper._init();
  static Database? _database;
  TestDBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('test_images.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            originalPath TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertImagePath(String path) async {
    final db = await instance.database;
    return await db.insert('images', {'originalPath': path});
  }

  Future<List<TestImageModel>> getAllImages() async {
    final db = await instance.database;
    final result = await db.query('images', orderBy: 'id DESC');

    final appDir = await getApplicationDocumentsDirectory();

    List<TestImageModel> list = [];
    for (var row in result) {
      final oldPath = row['originalPath'] as String;
      final fileName = p.basename(oldPath);
      final newFixedPath = p.join(appDir.path, fileName);

      list.add(
        TestImageModel(
          id: row['id'] as int,
          dbSavedPath: oldPath,
          currentFixedPath: newFixedPath,
        ),
      );
    }
    return list;
  }
}

// --- ARAYÜZ ---
class TestHomePage extends StatefulWidget {
  const TestHomePage({super.key});

  @override
  State<TestHomePage> createState() => _TestHomePageState();
}

class _TestHomePageState extends State<TestHomePage> {
  List<TestImageModel> _images = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);
    final data = await TestDBHelper.instance.getAllImages();
    setState(() {
      _images = data;
      _isLoading = false;
    });
  }

  Future<void> _pickAndSaveImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'test_soru_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImagePath = p.join(appDir.path, fileName);

      final savedFile = await File(pickedFile.path).copy(savedImagePath);

      await TestDBHelper.instance.insertImagePath(savedFile.path);

      _loadImages();
    } catch (e) {
      debugPrint("HATA OLUŞTU: $e");
    }
  }

  // YENİ EKLENEN: Klasörün içini canlı olarak listeleyen fonksiyon
  Future<void> _showDirectoryContents() async {
    final appDir = await getApplicationDocumentsDirectory();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // Klasördeki dosyaları anlık olarak oku
            final List<FileSystemEntity> files = appDir.listSync();

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Klasör İçeriği (${files.length} Öğe)",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          // Yenile butonuna basınca modalı günceller
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  Text(
                    appDir.path,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const Divider(),
                  Expanded(
                    child: files.isEmpty
                        ? const Center(child: Text("Klasör tamamen boş."))
                        : ListView.builder(
                            itemCount: files.length,
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final isFile = file is File;
                              final size = isFile ? file.lengthSync() : 0;
                              final name = p.basename(file.path);
                              final lastMod = isFile
                                  ? file.lastModifiedSync()
                                  : null;

                              return ListTile(
                                leading: Icon(
                                  isFile ? Icons.image : Icons.folder,
                                  color: isFile ? Colors.indigo : Colors.orange,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  isFile
                                      ? "${(size / 1024).toStringAsFixed(2)} KB\n${lastMod?.day}/${lastMod?.month}/${lastMod?.year} ${lastMod?.hour}:${lastMod?.minute}"
                                      : "Klasör",
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: isFile,
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    // Test amaçlı dosyayı fiziksel olarak sil
                                    if (isFile) {
                                      file.deleteSync();
                                      setModalState(() {}); // Modalı yenile
                                      _loadImages(); // Ana ekranı yenile
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "$name silindi!",
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDiagnosticLog(TestImageModel item) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File(item.currentFixedPath);
    final bool exists = file.existsSync();
    final int size = exists ? file.lengthSync() : 0;

    final dbDir = item.dbSavedPath.substring(
      0,
      item.dbSavedPath.lastIndexOf('/'),
    );
    final bool isSandboxChanged = dbDir != appDir.path;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("🔍 Detaylı Dosya Analizi"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Soru ID: ${item.id}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Divider(),
              Text(
                "Fiziksel Dosya Durumu:",
                style: TextStyle(
                  color: Colors.blue[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Mevcut Mu?: ${exists ? '✅ EVET' : '❌ HAYIR (SİLİNMİŞ)'}",
                style: TextStyle(
                  color: exists ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text("Boyut: ${(size / 1024).toStringAsFixed(2)} KB"),
              const Divider(),
              Text(
                "Sandbox (Klasör) Durumu:",
                style: TextStyle(
                  color: Colors.blue[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Değişmiş mi?: ${isSandboxChanged ? '⚠️ EVET (Güncellenmiş)' : '✅ HAYIR (Aynı)'}",
              ),
              const SizedBox(height: 10),
              const Text(
                "Veritabanına İlk Kaydedilen Yol (Eski):",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text(
                item.dbSavedPath,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text(
                "Şu Anki Güncel Klasör Yolu (Yeni):",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text(
                item.currentFixedPath,
                style: const TextStyle(fontSize: 10, color: Colors.indigo),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Kapat"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('TestFlight İzole Test'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadImages),
          // YENİ BUTON BURADA: KLASÖR İÇERİĞİNİ GÖR
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _showDirectoryContents,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndSaveImage,
        icon: const Icon(Icons.add_a_photo),
        label: const Text("Resim Ekle"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
          ? const Center(
              child: Text(
                "Henüz resim eklenmedi.\nSağ alttan ekleyin.",
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final item = _images[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () => _showDiagnosticLog(item),
                    child: Column(
                      children: [
                        Container(
                          height: 250,
                          width: double.infinity,
                          color: Colors.grey[300],
                          child: Image.file(
                            File(item.currentFixedPath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.broken_image,
                                    size: 50,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Resim Bulunamadı!",
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "Soru ID: ${item.id}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.white,
                          width: double.infinity,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Resim Kaydı #${item.id}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                "LOGLARI GÖR",
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
