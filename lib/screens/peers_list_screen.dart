import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models.dart';
import '../database_helper.dart';
import '../p2pmanager.dart';
import 'chat_screen.dart';

class PeersListScreen extends StatefulWidget {
  const PeersListScreen({super.key});

  @override
  State<PeersListScreen> createState() => _PeersListScreenState();
}

class _PeersListScreenState extends State<PeersListScreen> {
  final P2PManager _p2pManager = P2PManager();
  final DBHelper _dbHelper = DBHelper();
  
  List<Peer> _savedPeers = [];
  List<BleDiscoveredDevice> _discoveredPeers = [];
  List<dynamic> _connectedClients = []; // قائمة العملاء المتصلين بالـ Host
  bool _isDiscovering = false;
  bool _isConnected = false;
  String? _selectedRole; // 'host' or 'client'

  @override
  void initState() {
    super.initState();
    _loadSavedPeers();
    _setupP2PCallbacks();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];

    final statuses = await permissions.request();
    
    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (!allGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب منح جميع الأذونات لاستخدام التطبيق'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // طلب أذونات P2P من المكتبة مباشرة
      try {
        final p2pHost = FlutterP2pHost();
        final p2pGranted = await p2pHost.askP2pPermissions();
        if (!p2pGranted) {
          print('فشل منح أذونات P2P');
        }
      } catch (e) {
        print('خطأ في طلب أذونات P2P: $e');
      }
    }
  }

  void _setupP2PCallbacks() {
    _p2pManager.onPeersDiscovered = (peers) {
      setState(() {
        _discoveredPeers = peers;
      });
    };
    
    _p2pManager.onGroupCreated = (address) {
      setState(() {
        _isConnected = true;
        _isDiscovering = false; // إيقاف حالة البحث للـ Host
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء المجموعة بنجاح! العنوان: $address')),
      );
    };
    
    _p2pManager.onClientsChanged = (clients) {
      final previousCount = _connectedClients.length;
      setState(() {
        _connectedClients = clients;
      });
      
      // إشعار عند اتصال جهاز جديد فقط (عند زيادة العدد)
      if (clients.isNotEmpty && clients.length > previousCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اتصال جهاز جديد'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    };
  }

  Future<void> _loadSavedPeers() async {
    final peersData = await _dbHelper.getPeers();
    setState(() {
      _savedPeers = peersData.map((map) => Peer.fromMap(map)).toList();
    });
  }

  Future<void> _startDiscovery() async {
    // عرض خيار اختيار الدور
    _showRoleSelectionDialog();
  }

  void _showRoleSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'اختر دور الجهاز',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Host: ينشئ نقطة اتصال وينتظر الأجهزة الأخرى',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Client: يبحث عن الأجهزة ويتصل بها',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startAsHost();
            },
            child: Text(
              'Host (مضيف)',
              style: TextStyle(color: Color(0xFFe94560)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startAsClient();
            },
            child: Text(
              'Client (عميل)',
              style: TextStyle(color: Color(0xFFe94560)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAsHost() async {
    setState(() {
      _isDiscovering = true;
      _selectedRole = 'host';
    });
    
    final success = await _p2pManager.createGroup();
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إنشاء المجموعة')),
      );
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  Future<void> _startAsClient() async {
    setState(() {
      _isDiscovering = true;
      _selectedRole = 'client';
    });
    await _p2pManager.startDiscovery();
  }

  Future<void> _connectToDevice(BleDiscoveredDevice device) async {
    final success = await _p2pManager.connectToDevice(device);
    if (success) {
      setState(() {
        _isConnected = true;
        _isDiscovering = false; // إيقاف البحث بعد الاتصال
      });
      
      // حفظ الجهاز إذا لم يكن موجوداً
      final existingPeer = await _dbHelper.getPeer(device.deviceAddress);
      if (existingPeer == null) {
        await _dbHelper.insertPeer(device.deviceAddress, device.deviceName);
        await _loadSavedPeers();
      }
      
      _navigateToChat(device.deviceAddress, device.deviceName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل الاتصال بالجهاز')),
      );
    }
  }

  void _navigateToChat(String peerId, String peerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          peerId: peerId,
          peerName: peerName,
          p2pManager: _p2pManager,
        ),
      ),
    ).then((_) {
      _loadSavedPeers();
    });
  }

  Future<void> _deletePeer(Peer peer) async {
    await _dbHelper.deletePeer(peer.id);
    await _loadSavedPeers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      _buildTabBar(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildSavedPeersList(),
                            _buildDiscoveredPeersList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby Chat',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _isConnected ? 'متصل' : 'غير متصل',
                        style: TextStyle(
                          fontSize: 14,
                          color: _isConnected ? Colors.greenAccent : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_selectedRole != null) ...[
                        SizedBox(width: 12),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFFe94560).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _selectedRole == 'host' ? 'HOST' : 'CLIENT',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFe94560),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.wifi_tethering,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: Color(0xFFe94560),
          borderRadius: BorderRadius.circular(16),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        tabs: [
          Tab(text: 'المحادثات المحفوظة'),
          Tab(text: 'الأجهزة القريبة'),
        ],
      ),
    );
  }

  Widget _buildSavedPeersList() {
    if (_savedPeers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            SizedBox(height: 16),
            Text(
              'لا توجد محادثات محفوظة',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _savedPeers.length,
      itemBuilder: (context, index) {
        final peer = _savedPeers[index];
        return _buildPeerTile(peer);
      },
    );
  }

  Widget _buildPeerTile(Peer peer) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFe94560), Color(0xFF0f3460)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          peer.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: peer.lastMessage.isNotEmpty
            ? Text(
                peer.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              )
            : null,
        trailing: peer.lastMessageTime.isNotEmpty
            ? Text(
                _formatTime(peer.lastMessageTime),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              )
            : null,
        onTap: () => _navigateToChat(peer.id, peer.name),
        onLongPress: () => _showDeleteDialog(peer),
      ),
    );
  }

  Widget _buildDiscoveredPeersList() {
    // إذا كان Host ومتصل، عرض الأجهزة المتصلة
    if (_selectedRole == 'host' && _isConnected) {
      if (_connectedClients.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_tethering,
                size: 80,
                color: Color(0xFFe94560),
              ),
              SizedBox(height: 16),
              Text(
                'بانتظار اتصال الأجهزة...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'العنوان: 192.168.49.1',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      } else {
        // عرض قائمة الأجهزة المتصلة
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'الأجهزة المتصلة (${_connectedClients.length})',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              itemCount: _connectedClients.length,
              itemBuilder: (context, index) {
                final client = _connectedClients[index];
                return _buildConnectedClientTile(client, index);
              },
            ),
          ],
        );
      }
    }

    if (!_isDiscovering) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            SizedBox(height: 16),
            Text(
              'اضغط على الزر للبحث عن الأجهزة',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_discoveredPeers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFe94560)),
            ),
            SizedBox(height: 16),
            Text(
              'جاري البحث عن الأجهزة...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _discoveredPeers.length,
      itemBuilder: (context, index) {
        final device = _discoveredPeers[index];
        return _buildDiscoveredDeviceTile(device);
      },
    );
  }

  Widget _buildDiscoveredDeviceTile(BleDiscoveredDevice device) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(0xFFe94560).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFe94560), Color(0xFF0f3460)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Icon(
              Icons.devices,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        title: Text(
          device.deviceName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          device.deviceAddress,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Color(0xFFe94560),
          size: 20,
        ),
        onTap: () => _connectToDevice(device),
      ),
    );
  }

  Widget _buildConnectedClientTile(dynamic client, int index) {
    String clientName = 'جهاز ${index + 1}';
    String clientId = 'client_$index';
    
    // محاولة استخراج معلومات من الكائن
    try {
      if (client is Map) {
        clientName = client['name'] ?? clientName;
        clientId = client['id']?.toString() ?? clientId;
      }
    } catch (e) {
      print('خطأ في قراءة بيانات العميل: $e');
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.green.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green, Color(0xFF0f3460)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        title: Text(
          clientName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'متصل',
          style: TextStyle(
            color: Colors.green.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.chat,
          color: Colors.green,
          size: 20,
        ),
        onTap: () => _navigateToChat(clientId, clientName),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: FloatingActionButton.extended(
        onPressed: _isDiscovering ? null : _startDiscovery,
        backgroundColor: Color(0xFFe94560),
        icon: Icon(_isDiscovering ? Icons.hourglass_empty : Icons.search),
        label: Text(_isDiscovering ? 'جاري البحث...' : 'بحث عن أجهزة'),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  void _showDeleteDialog(Peer peer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'حذف المحادثة',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'هل تريد حذف محادثة ${peer.name}؟',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(color: Color(0xFFe94560)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePeer(peer);
            },
            child: Text(
              'حذف',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} د';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} س';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
