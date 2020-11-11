import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';

class Gist {
  final String id;
  final String url;
  final String description;
  var files = <String, Object>{};
  final User owner;

  Gist({this.id, this.url, this.description, this.files, this.owner});

  factory Gist.fromJson(Map<String, dynamic> json) {
    var fileMap = Map<String, Object>();
    json['files'].forEach((key, value) {
      fileMap.addAll({key: File.fromJson(value)});
    });

    return Gist(
      id: json['id'],
      url: json['html_url'],
      description: json['description'],
      files: fileMap,
      owner: User.fromJson(json["owner"]),
    );
  }
}

class File {
  final String filename;
  final String rawUrl;

  File({this.filename, this.rawUrl});

  factory File.fromJson(Map<String, dynamic> json) {
    return File(filename: json['filename'], rawUrl: json['raw_url']);
  }
}

class User {
  final String login;
  final String avatarUrl;

  User({this.login, this.avatarUrl});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(login: json['login'], avatarUrl: json['avatar_url']);
  }
}

List<Gist> parseGists(String responseBody) {
  final parsed = jsonDecode(responseBody).cast<Map<String, dynamic>>();
  return parsed.map<Gist>((json) => Gist.fromJson(json)).toList();
}

Future<List<Gist>> fetchGists(http.Client client) async {
  String apiUrl = 'https://api.github.com/gists/public';
  final response = await client.get(apiUrl);
  return compute(parseGists, response.body);
}

Future<String> fetchContent(http.Client client, String url) async {
  final response = await client.get(url);
  return response.body.toString();
}

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return MaterialApp(
            title: 'Gists',
            home: GistList(),
            theme: ThemeData(
                primaryColor: Colors.blueGrey,
                accentColor: Colors.indigoAccent),
          );
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}

class GistList extends StatefulWidget {
  @override
  _GistListState createState() => _GistListState();
}

class _GistListState extends State<GistList> {
  Future<List<Gist>> _gistList;
  var _starred = List<String>();

  void getStarred() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> ids = prefs.getStringList('gistIds');
    setState(() {
      if (ids != null) {
        if (_starred.isNotEmpty) {
          _starred.addAll(ids);
        } else {
          _starred = ids;
        }
      }
    });
  }

  void setStarred(gist) async {
    final alreadySaved = _starred.contains(gist);
    SharedPreferences prefs = await SharedPreferences.getInstance();

    setState(() {
      if (!alreadySaved) {
        _starred.add(gist);
      } else {
        _starred.remove(gist);
      }
    });

    prefs.setStringList('gistIds', _starred);
  }

  @override
  void initState() {
    super.initState();
    getStarred();

    _gistList = fetchGists(http.Client());
  }

  void _pushSaved() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Starred'),
            ),
            body: _buildSavedList(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gists'),
        actions: [
          IconButton(icon: Icon(Icons.star), onPressed: _pushSaved),
        ],
      ),
      body: _buildList(),
    );
  }

  Widget _buildList() {
    return FutureBuilder(
      future: _gistList,
      builder: (BuildContext context, snapshot) {
        if (snapshot.hasData) {
          return ListView.builder(
            itemCount: snapshot.data.length,
            itemBuilder: (context, index) {
              return _buildRow(snapshot.data[index]);
            },
          );
        } else if (snapshot.hasError) {
          return Text(snapshot.error.toString());
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildSavedList() {
    return FutureBuilder(
        future: _gistList,
        builder: (BuildContext context, snapshot) {
          if (snapshot.hasData) {
            return ListView.builder(
              itemCount: _starred.length,
              itemBuilder: (context, index) {
                if (_starred.contains(snapshot.data[index].id)) {
                  return _buildRow(snapshot.data[index]);
                }
                return null;
              },
            );
          } else if (snapshot.hasError) {
            return Text(snapshot.error.toString());
          }

          return Center(child: CircularProgressIndicator());
        });
  }

  Widget _buildRow(gist) {
    final _alreadyStarred = _starred.contains(gist.id);
    final _firstFile = gist.files.values.toList()[0];

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: NetworkImage(gist.owner.avatarUrl),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text(gist.owner.login),
                          Text(" / "),
                          InkWell(
                              child: Text(_firstFile.filename,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black)),
                              onTap: () => launch(gist.url)),
                          IconButton(
                            icon: Icon(_alreadyStarred
                                ? Icons.star
                                : Icons.star_border),
                            onPressed: () {
                              setStarred(gist.id);
                            },
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  child: Text(gist.description != null ? gist.description : "",
                      style: TextStyle(fontSize: 12)),
                  alignment: Alignment.centerLeft,
                ),
                Container(
                  child: _buildContent(_firstFile.rawUrl),
                  alignment: Alignment.centerLeft,
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildContent(url) {
    return SizedBox(
      width: double.infinity,
      height: 110,
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(8),
          child: FutureBuilder(
            future: fetchContent(http.Client(), url),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Text(
                  snapshot.data,
                  overflow: TextOverflow.fade,
                );
              } else if (snapshot.hasError) {
                return Text(snapshot.error.toString());
              }
              return Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }
}
