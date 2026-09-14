import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';

import 'services/receipt_ocr_service.dart';
import 'database/ledger_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartLedgerApp());
}

class SmartLedgerApp extends StatelessWidget {
  const SmartLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '离线智能账本',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        useMaterial3: true,
      ),
      home: const LedgerHomeScreen(),
    );
  }
}

class LedgerHomeScreen extends StatefulWidget {
  const LedgerHomeScreen({super.key});

  @override
  State<LedgerHomeScreen> createState() => _LedgerHomeScreenState();
}

class _LedgerHomeScreenState extends State<LedgerHomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  List<Map<String, dynamic>> _receipts = [];
  double _totalMonthlySpent = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLedgerData();
  }

  Future<void> _loadLedgerData() async {
    final db = await LedgerDatabase.instance.database;
    final receipts = await db.query('receipts', orderBy: 'trans_datetime DESC');

    double sum = 0.0;
    for (var r in receipts) {
      sum += (r['total_amount'] as num?)?.toDouble() ?? 0.0;
    }

    setState(() {
      _receipts = receipts;
      _totalMonthlySpent = sum;
    });
  }

  Map<String, dynamic> _parseReceiptLocally(String alignedText) {
    final lines = alignedText.split('\n');
    String merchant = lines.isNotEmpty ? lines.first : '未知商家';

    RegExp dateReg = RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}(\s+\d{2}:\d{2}(:\d{2})?)?');
    String transDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    for (var line in lines) {
      final match = dateReg.firstMatch(line);
      if (match != null) {
        transDate = match.group(0)!;
        break;
      }
    }

    RegExp priceReg = RegExp(r'(\d+\.\d{2})');
    List<Map<String, dynamic>> items = [];
    double calculatedTotal = 0.0;

    for (var line in lines) {
      final matches = priceReg.allMatches(line).toList();
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        double? price = double.tryParse(lastMatch.group(0)!);
        if (price != null) {
          String itemName = line.substring(0, lastMatch.start).replaceAll(RegExp(r'[\d\.\-\:]+'), '').trim();
          if (itemName.isEmpty) itemName = '消费细项';

          String category = '日用商超';
          if (itemName.contains('咖啡') || itemName.contains('餐') || itemName.contains('饭') || itemName.contains('茶')) {
            category = '餐饮美食';
          } else if (itemName.contains('车') || itemName.contains('地铁') || itemName.contains('打车')) {
            category = '交通出行';
          }

          items.add({
            'name': itemName,
            'price': price,
            'quantity': 1.0,
            'amount': price,
            'category': category
          });
          calculatedTotal += price;
        }
      }
    }

    return {
      'merchant': merchant,
      'datetime': transDate,
      'items': items,
      'total_amount': calculatedTotal > 0 ? calculatedTotal : 0.0,
      'payment_method': alignedText.contains('微信') ? '微信支付' : (alignedText.contains('支付宝') ? '支付宝' : '现金/其他')
    };
  }

  Future<void> _processImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source);
    if (file == null) return;

    setState(() => _isProcessing = true);

    try {
      final boxes = await ReceiptOcrService.recognizeImage(file.path);
      final alignedText = ReceiptOcrService.alignBoxesToText(boxes);
      final parsedData = _parseReceiptLocally(alignedText);

      await LedgerDatabase.instance.insertReceipt(parsedData, alignedText);
      await _loadLedgerData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B).withOpacity(0.9),
            content: Text('成功记入：${parsedData['merchant']} ￥${parsedData['total_amount']}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // 背景液态冷色光斑
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.tealAccent.withOpacity(0.25), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.cyan.withOpacity(0.2), Colors.transparent],
                ),
              ),
            ),
          ),

          // 主体内容
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '智能账本',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                // 顶部汇总流体卡片
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('本月支出累计', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                          const SizedBox(height: 8),
                          Text(
                            '￥${_totalMonthlySpent.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: const Icon(Icons.shield_outlined, color: Colors.tealAccent, size: 28),
                      ),
                    ],
                  ),
                ),

                // 账单瀑布流列表
                Expanded(
                  child: _isProcessing
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.tealAccent),
                              SizedBox(height: 20),
                              Text('NPU 离线几何行聚类中...', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        )
                      : _receipts.isEmpty
                          ? Center(
                              child: Text(
                                '暂无小票记录\n点击下方液态玻璃胶囊拍照',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withOpacity(0.35), height: 1.6),
                              ),
                            )
                          : MasonryGridView.count(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              itemCount: _receipts.length,
                              itemBuilder: (context, index) {
                                final r = _receipts[index];
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['merchant'] ?? '未知商家',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '￥${((r['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 20, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        r['trans_datetime'] ?? '',
                                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),

          // 核心：iOS 液态玻璃悬浮胶囊按键 (Liquid Glass Button)
          Positioned(
            left: 0,
            right: 0,
            bottom: 34,
            child: Center(
              child: LiquidGlassButton(
                onTap: () => _processImage(ImageSource.camera),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      '拍小票记账',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS 液态玻璃按钮组件 (Liquid Glassmorphism)
class LiquidGlassButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const LiquidGlassButton({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              // 液态外发光弥散光晕
              BoxShadow(
                color: Colors.tealAccent.withOpacity(0.28),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
              // 深层悬浮投影
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              // 亚克力高斯模糊（iOS 磨砂质感核心）
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  // 双层液态通透折射渐变
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.28),
                      Colors.white.withOpacity(0.08),
                      Colors.tealAccent.withOpacity(0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
