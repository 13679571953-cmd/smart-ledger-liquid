import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class LedgerDatabase {
  static final LedgerDatabase instance = LedgerDatabase._init();
  static Database? _database;

  LedgerDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('secure_ledger.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final path = join(docDir.path, filePath);
    const dbPassword = "SecretLedgerKey#2026";

    return await openDatabase(
      path,
      password: dbPassword,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            merchant TEXT,
            trans_datetime TEXT,
            total_amount REAL,
            payment_method TEXT,
            raw_ocr TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE receipt_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            receipt_id INTEGER,
            item_name TEXT,
            price REAL,
            quantity REAL,
            amount REAL,
            category TEXT,
            FOREIGN KEY (receipt_id) REFERENCES receipts (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<int> insertReceipt(Map<String, dynamic> data, String rawOcr) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      int receiptId = await txn.insert('receipts', {
        'merchant': data['merchant'] ?? '未知商家',
        'trans_datetime': data['datetime'] ?? DateTime.now().toString(),
        'total_amount': (data['total_amount'] as num?)?.toDouble() ?? 0.0,
        'payment_method': data['payment_method'] ?? '未知',
        'raw_ocr': rawOcr,
      });

      List items = data['items'] ?? [];
      for (var item in items) {
        await txn.insert('receipt_items', {
          'receipt_id': receiptId,
          'item_name': item['name'] ?? '商品',
          'price': (item['price'] as num?)?.toDouble() ?? 0.0,
          'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
          'category': item['category'] ?? '其他支出',
        });
      }
      return receiptId;
    });
  }
}
