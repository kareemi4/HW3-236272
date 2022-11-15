import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:english_words/english_words.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snapping_sheet/snapping_sheet.dart';

enum Status { Uninitialized, Authenticated, Authenticating, Unauthenticated }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(App());

}

class AuthRepository with ChangeNotifier {
  FirebaseAuth _auth;
  User? _user;
  Status _status = Status.Uninitialized;
  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseStorage _storage = FirebaseStorage.instance;
  Set<WordPair> favourites = new Set<WordPair>();

  AuthRepository.instance() : _auth = FirebaseAuth.instance {
    _auth.authStateChanges().listen(_onAuthStateChanged);
    _user = _auth.currentUser;
    _onAuthStateChanged(_user);
  }

  Status get status => _status;

  User? get user => _user;

  bool get isAuthenticated => status == Status.Authenticated;

  String? getUserEmail() {
    return _user!.email;
  }

  Future<void> uploadImage(File file) async {
    await _storage.ref('images').child(_user!.uid).putFile(file);
    notifyListeners();
  }

  Future<String> getDownloadUrl() async {
    return await _storage.ref('images').child(_user!.uid).getDownloadURL();
  }

  Future<UserCredential?> signUp(String email, String password) async {
    try {
      _status = Status.Authenticating;
      notifyListeners();
      return await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } catch (e) {
      print(e);
      _status = Status.Unauthenticated;
      notifyListeners();
      return null;
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _status = Status.Authenticating;
      notifyListeners();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      favourites = await getfavourites();
      notifyListeners();
      return true;
    } catch (e) {
      _status = Status.Unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future signOut() async {
    _auth.signOut();
    _status = Status.Unauthenticated;
    notifyListeners();
    return Future.delayed(Duration.zero);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _user = null;
      _status = Status.Unauthenticated;
    } else {
      _user = firebaseUser;
      _status = Status.Authenticated;
      favourites = await getfavourites();
    }
    notifyListeners();
  }

  Future<Set<WordPair>> getfavourites() async {
    Set<WordPair> s = new Set<WordPair>();
    await _firestore
        .collection("users")
        .doc(_user!.uid)
        .collection('favourites')
        .get()
        .then((querySnapshot) {
      querySnapshot.docs.forEach((result) {
        String first = result.data().entries.first.value.toString();
        String second = result.data().entries.last.value.toString();
        s.add(WordPair(first, second));
      });
    });
    return Future<Set<WordPair>>.value(s);
  }

  Set<WordPair> getuploadedfavourites() {
    return favourites;
  }

  void addPair(WordPair pair) async {
    if (_status == Status.Authenticated) {
      await _firestore
          .collection("users")
          .doc(_user!.uid)
          .collection("favourites")
          .doc(pair.toString())
          .set({
        'first': pair.first.toString(),
        'second': pair.second.toString()
      });
    }
    favourites = await getfavourites();
    notifyListeners();
  }

  void removePair(WordPair pair) async {
    if (_status == Status.Authenticated) {
      await _firestore
          .collection("users")
          .doc(_user!.uid)
          .collection('favourites')
          .doc(pair.toString())
          .delete();
      favourites = await getfavourites();
      notifyListeners();
    }
  }
}

class App extends StatelessWidget {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text(snapshot.error.toString(),
                      textDirection: TextDirection.ltr)));
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return MyApp();
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthRepository.instance(),
      child: Consumer<AuthRepository>(
        builder: (context, login, _) => MaterialApp(
          theme: ThemeData(
              appBarTheme: const AppBarTheme(color: Colors.deepPurple)),
          title: 'Startup Name Generator',
          initialRoute: '/',
          routes: {
            '/': (context) => RandomWords(),
            '/login': (context) => LoginScreen(),
          },
        ),
      ),
    );
  }
}

class RandomWords extends StatefulWidget {
  @override
  _RandomWordsState createState() => _RandomWordsState();
}

class _RandomWordsState extends State<RandomWords> {
  final _suggestions = <WordPair>[];
  final _biggerFont = const TextStyle(fontSize: 18);
  final _saved = <WordPair>{};
  SnappingSheetController _snappingSheetController = SnappingSheetController();
  bool drag = false;
  var user;

  // final AuthRepository _auth = AuthRepository.instance();

  void _pushSaved() {
    Navigator.of(context).push(
      // Add lines from here...
      MaterialPageRoute<void>(
        builder: (context) {
          final user = Provider.of<AuthRepository>(context);

          var favourites = _saved;
          if (user._status == Status.Authenticated) {
            favourites = user.getuploadedfavourites();
          } else {
            favourites = _saved;
          }

          final tiles = favourites.map(
                (pair) {
              return Dismissible(
                key: ValueKey<int>(pair.hashCode),
                child: ListTile(
                  title: Text(
                    pair.asPascalCase,
                    style: _biggerFont,
                  ),
                ),
                background: Container(
                  color: Colors.deepPurple,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete,
                        color: Colors.white,
                      ),
                      Text(
                        'Delete Suggestion',
                        style: TextStyle(color: Colors.white),
                      )
                    ],
                  ),
                ),
                onDismissed: (DismissDirection) async {
                  user.removePair(pair);
                  _saved.remove(pair);
                  setState(() {});
                },
                confirmDismiss: (DismissDirection direction) async {
                  final deletion = pair.asPascalCase;

                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Delete Suggestion"),
                        content: Text(
                            "are you sure you want to delete ${deletion} from your saved suggestions?"),
                        actions: <Widget>[
                          ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text(
                                "Yes",
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                primary: Colors.deepPurple,
                              )),
                          ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text(
                                "No",
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                primary: Colors.deepPurple,
                              )),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
          final divided = tiles.isNotEmpty
              ? ListTile.divideTiles(
            context: context,
            tiles: tiles,
          ).toList()
              : <Widget>[];

          return Scaffold(
            appBar: AppBar(
              title: const Text('Saved Suggestions'),
            ),
            body: ListView(children: divided),
          );
        },
      ), // ...to here.
    );
  }

  Widget _buildSuggestions() {
    return ListView.builder(
        padding: const EdgeInsets.all(16),
        // The itemBuilder callback is called once per suggested
        // word pairing, and places each suggestion into a ListTile
        // row. For even rows, the function adds a ListTile row for
        // the word pairing. For odd rows, the function adds a
        // Divider widget to visually separate the entries. Note that
        // the divider may be difficult to see on smaller devices.
        itemBuilder: (BuildContext _context, int i) {
          // Add a one-pixel-high divider widget before each row
          // in the ListView.
          if (i.isOdd) {
            return Divider();
          }

          // The syntax "i ~/ 2" divides i by 2 and returns an
          // integer result.
          // For example: 1, 2, 3, 4, 5 becomes 0, 1, 1, 2, 2.
          // This calculates the actual number of word pairings
          // in the ListView,minus the divider widgets.
          final int index = i ~/ 2;
          // If you've reached the end of the available word
          // pairings...
          if (index >= _suggestions.length) {
            // ...then generate 10 more and add them to the
            // suggestions list.
            _suggestions.addAll(generateWordPairs().take(10));
          }

          return _buildRow(_suggestions[index]);
        });
  }

  Widget _buildRow(WordPair pair) {
    final alreadySaved = _saved.contains(pair) ||
        (user.getuploadedfavourites().contains(pair) &&
            user._status == Status.Authenticated);
    final uploaded = user.getuploadedfavourites().contains(pair) &&
        user._status == Status.Authenticated;

    final savedlocaly = _saved.contains(pair);
    if (!uploaded && savedlocaly) {
      user.addPair(pair);
    }

    return ListTile(
      title: Text(
        pair.asPascalCase,
        style: _biggerFont,
      ),
      trailing: Icon(
        alreadySaved ? Icons.star : Icons.star_border,
        color: alreadySaved ? Colors.deepPurple : null,
        semanticLabel: alreadySaved ? 'Remove from saved' : 'Save',
      ),
      onTap: () {
        // NEW lines from here...
        setState(() {
          if (alreadySaved) {
            _saved.remove(pair);
            user.removePair(pair);
          } else {
            _saved.add(pair);
            user.addPair(pair);
          }
        });
      }, // ... to here.
    );
  }

  @override
  Widget build(BuildContext context) {
    user = Provider.of<AuthRepository>(context);

    var icon_to_view = Icons.login;
    var function_on_press = _login;
    if (user._status == Status.Authenticated) {
      icon_to_view = Icons.exit_to_app;
      function_on_press = _logout;
    }
    return Scaffold(
        appBar: AppBar(
          title: Text('Startup Name Generator'),
          actions: [
            IconButton(
              icon: const Icon(Icons.star),
              onPressed: _pushSaved,
              tooltip: 'Saved Suggestions',
            ),
            IconButton(
              icon: Icon(icon_to_view),
              onPressed: function_on_press,
            )
          ],
        ),
        body: GestureDetector(
          child: SnappingSheet(
            controller: _snappingSheetController,
            snappingPositions: [
              SnappingPosition.pixels(
                  positionPixels: 220,
                  snappingCurve: Curves.bounceOut,
                  snappingDuration: Duration(milliseconds: 350)),
              SnappingPosition.factor(
                  positionFactor: 1.1,
                  snappingCurve: Curves.easeInBack,
                  snappingDuration: Duration(milliseconds: 2)),
            ],
            lockOverflowDrag: true,
            onSnapCompleted: _onCompleted,
            initialSnappingPosition:
            SnappingPosition.factor(positionFactor: 0.074),
            child: _buildSuggestions(),
            sheetBelow: user._status == Status.Authenticated
                ? SnappingSheetContent(
              draggable: drag,
              child: Container(
                color: Colors.white,
                child: ListView(
                    physics: NeverScrollableScrollPhysics(),
                    children: [
                      Column(children: [
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Container(
                                color: Colors.grey,
                                height: 50,
                                child: Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Flexible(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            Padding(
                                              padding:
                                              EdgeInsets.all(10.0),
                                              child: Center(
                                                child: Text(
                                                    "Welcome back, " +
                                                        user
                                                            .getUserEmail(),
                                                    style: TextStyle(
                                                        fontSize: 14.0)),
                                              ),
                                            ),
                                          ],
                                        )),
                                    IconButton(
                                      icon: Icon(Icons.keyboard_arrow_up),
                                      onPressed: null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: EdgeInsets.all(10),
                        ),
                        Row(children: <Widget>[
                          FutureBuilder(
                            future: user.getDownloadUrl(),
                            builder: (BuildContext context,
                                AsyncSnapshot<String> snapshot) {
                              return Padding(
                                padding: EdgeInsets.all(10.0),
                                child: CircleAvatar(
                                  radius: 40.0,
                                  backgroundImage: snapshot.data != null
                                      ? NetworkImage(snapshot.data!)
                                      : null,
                                ),
                              );
                            },
                          ),
                          Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(user.getUserEmail(),
                                  style: TextStyle(fontSize: 18))),
                        ]),
                        Row(
                            children:<Widget>[MaterialButton(
                              onPressed: () async {
                                FilePickerResult? result =
                                await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: [
                                    'png',
                                    'jpg',
                                    'gif',
                                    'bmp',
                                    'jpeg',
                                    'webp'
                                  ],
                                );
                                File file;
                                if (result != null) {
                                  file = File(result.files.single.path!);
                                  user.uploadImage(file);
                                }else{
                                  final snackbar = SnackBar(
                                    content: Text('No image selected'),
                                    backgroundColor: Colors.deepPurple,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(snackbar);
                                }
                              },
                              textColor: Colors.white,
                              padding: EdgeInsets.only(
                                left: 10.0,
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                ),
                                padding: const EdgeInsets.all(5.0),
                                child: const Text('Change Avatar',
                                    style: TextStyle(fontSize: 15)),
                              ),
                            ),]
                        ),
                      ]),
                    ]),
              ),
              //heightBehavior: SnappingSheetHeight.fit(),
            )
                : null,
          ),
          onTap: () => {
            setState(() {
              if (drag == false) {
                drag = true;

                _snappingSheetController.snapToPosition(SnappingPosition.factor(
                  positionFactor: 0.37,
                  snappingDuration: Duration(milliseconds: 500),
                ));
              } else {
                drag = false;
                _snappingSheetController.snapToPosition(SnappingPosition.factor(
                    positionFactor: 0.074,
                    snappingCurve: Curves.easeInBack,
                    snappingDuration: Duration(milliseconds: 300)));
              }
            })
          },
        ));
  }

  dynamic _onCompleted(_data, SnappingPosition _position) {
    if (drag == true) {
      _snappingSheetController.stopCurrentSnapping();
      _snappingSheetController.snapToPosition(SnappingPosition.factor(
          positionFactor: 0.37, snappingCurve: Curves.easeInBack));
    } else {
      _snappingSheetController.snapToPosition(SnappingPosition.factor(
          positionFactor: 0.074,
          snappingCurve: Curves.easeInBack,
          snappingDuration: Duration(milliseconds: 30)));
    }
  }

  void _login() {
    _saved.clear();
    Navigator.of(context).pushNamed('/login');
  }

  void _logout() async {
    await user.signOut();
    final snackbar = SnackBar(
      content: Text('Successfully logged out'),
      backgroundColor: Colors.deepPurple,
    );
    ScaffoldMessenger.of(context).showSnackBar(snackbar);
    _saved.clear();
    setState(() {});
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreen createState() => _LoginScreen();
}

class _LoginScreen extends State<LoginScreen> {
  var scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthRepository>(context);
    TextEditingController emailcontroller = new TextEditingController();
    TextEditingController passwordcontroller = new TextEditingController();
    TextEditingController _confirmPassword = new TextEditingController();
    bool validation = true;

    String? _error = validation ? null : 'Passwords must match';

    return Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          title: const Text('Login'),
        ),
        body: Column(
          children: <Widget>[
            const Padding(padding: EdgeInsets.all(25)),
            Text(
              'Welcome to Startup Names Generator, please log in below',
              style: TextStyle(fontSize: 17),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            TextField(
              controller: emailcontroller,
              decoration: const InputDecoration(
                  labelText: 'Email', labelStyle: TextStyle(fontSize: 20)),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            TextField(
              controller: passwordcontroller,
              decoration: const InputDecoration(
                  labelText: 'Password', labelStyle: TextStyle(fontSize: 20)),
              obscureText: true,
            ),
            const Padding(padding: EdgeInsets.all(10)),
            user.status == Status.Authenticating
                ? Center(
                child: CircularProgressIndicator(
                  color: Colors.deepPurple,
                  backgroundColor: Colors.white,
                ))
                : ElevatedButton(
              onPressed: () async {
                bool res = await user.signIn(
                    emailcontroller.text, passwordcontroller.text);

                if (res == false) {
                  final snackbar = SnackBar(
                    content:
                    Text('There was an error logging into the app'),
                    backgroundColor: Colors.deepPurple,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackbar);
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text(
                'Log in',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                primary: Colors.deepPurple,
                onPrimary: Colors.white,
                shape: new RoundedRectangleBorder(
                  borderRadius: new BorderRadius.circular(30.0),
                ),
                fixedSize: const Size(390, 40),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                    isScrollControlled: true,
                    context: context,
                    builder: (BuildContext context) {
                      return Container(
                        height: 300,
                        child: Column(
                          children: <Widget>[
                            Center(
                              child: Padding(
                                padding: EdgeInsets.all(15),
                                child: const Text(
                                  'Please confirm your password below:',
                                  style: TextStyle(fontSize: 17),
                                ),
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Padding(
                                  padding: EdgeInsets.all(10),
                                  child: const Text('Password'),
                                )
                              ],
                            ),
                            TextField(
                              decoration: InputDecoration(
                                  errorText: validation
                                      ? null
                                      : 'Passwords must match'),
                              obscureText: true,
                              controller: _confirmPassword,
                            ),
                            Padding(
                              padding: EdgeInsets.all(5),
                            ),
                            Center(
                              child: MaterialButton(
                                onPressed: () async {
                                  if (_confirmPassword.text ==
                                      passwordcontroller.text) {
                                    user.signUp(emailcontroller.text,
                                        _confirmPassword.text);

                                    //   bool res = await user.signIn(emailcontroller.text, passwordcontroller.text);

                                    Navigator.of(context).pop();
                                    Navigator.of(context).pop();
                                    setState(() {});
                                  } else {
                                    validation = false;
                                    setState(() {
                                      FocusScope.of(context)
                                          .requestFocus(FocusNode());
                                    });
                                  }
                                },
                                textColor: Colors.white,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                  ),
                                  padding: const EdgeInsets.all(5.0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                    ),
                                    padding: const EdgeInsets.all(5.0),
                                    child: const Text('Confirm',
                                        style: TextStyle(fontSize: 15)),
                                  ),
                                ),
                              ),
                            )
                          ],
                        ),
                      );
                    });
              },
              child: const Text(
                'New user? Click to sign up',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                primary: Colors.blue,
                onPrimary: Colors.white,
                shape: new RoundedRectangleBorder(
                  borderRadius: new BorderRadius.circular(30.0),
                ),
                fixedSize: const Size(390, 40),
              ),
            )
          ],
        ));
  }
}