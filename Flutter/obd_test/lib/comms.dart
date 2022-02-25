import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'OBD_PID.dart';

class _message {
  int whom;
  String text;

  _message(this.whom, this.text);
  _message.fromList(List<String> str) {
    whom = int.parse(str[0]);
    text = str[1];
  }
}

class carInfo {
  static BluetoothDevice _server = null;
  static BluetoothConnection _connection;
  static bool _connected = false;
  static bool _scanning = false;
  static bool _disconnecting = false;

  static List<_message> messages = List<_message>.empty(growable: true);
  static String _messageBuffer = '';

  static List<bool> _scanPID =
      List.generate(OBDPid.LAST_INDEX.index, (index) => false);
  static List<int> _values =
      List.generate(OBDPid.LAST_INDEX.index, (index) => 0);

  static int battery_charge = 0;

  carInfo();

  void randomize() {
    var rand = Random();

    _values[OBDPid.ENGINE_SPEED.index] = rand.nextInt(8000);
    _values[OBDPid.CALCULATED_ENGINE_LOAD.index] = rand.nextInt(100);
    _values[OBDPid.ENGINE_COOLANT_TEMPERATURE.index] = rand.nextInt(200);
    _values[OBDPid.FUEL_TANK_LEVEL_INPUT.index] = rand.nextInt(100);
    _values[OBDPid.VEHICLE_SPEED.index] = rand.nextInt(200);
    _values[OBDPid.THROTTLE_POSITION.index] = rand.nextInt(100);
    battery_charge = 42;
  }

  void switchTest() {
    _scanPID[OBDPid.ENGINE_SPEED.index] = true;
    _scanPID[OBDPid.CALCULATED_ENGINE_LOAD.index] = true;
    _scanPID[OBDPid.ENGINE_COOLANT_TEMPERATURE.index] = true;
    _scanPID[OBDPid.FUEL_TANK_LEVEL_INPUT.index] = true;
    _scanPID[OBDPid.VEHICLE_SPEED.index] = true;
    _scanPID[OBDPid.THROTTLE_POSITION.index] = true;
  }

  void scanAll() async {
    int i = 0;

    while (i < OBDPid.LAST_INDEX.index) {
      await scanItem(i++, _scanMethod);
    }
  }

  void scanItem(int pidIndex, Function scanMethod) {
    if (_scanPID[pidIndex] == false) {
      _values[pidIndex] = -1;
    } else {
      scanMethod(pidIndex);
    }
  }

  int _scanMethod(int pidIndex) {
    var rand = Random();

    if (_server == null) {
      print("Tried scan without being connected to OBD");
      return -2;
    } else {
      battery_charge = 90;
      _sendMessage(PidName[pidIndex]);
      return 42;
    }
  }

  void startComm(BuildContext context, BluetoothDevice server) {
    _server = server;

    BluetoothConnection.toAddress(server.address).then((__connection) {
      print('Connected to the device');
      _connection = __connection;
      _disconnecting = false;

      _connection.input.listen(_onDataReceived).onDone(() {
        // Example: Detect which side closed the connection
        // There should be `isDisconnecting` flag to show are we are (locally)
        // in middle of disconnecting process, should be set before calling
        // `dispose`, `finish` or `close`, which all causes to disconnect.
        // If we except the disconnection, `onDone` should be fired as result.
        // If we didn't except this (no flag set), it means closing by remote.
        if (_disconnecting) {
          print('Disconnecting locally!');
        } else {
          print('Disconnected remotely!');
        }
      });
    }).catchError((error) {
      print('Cannot connect, exception occured');
      print(error);
    });
  }

  void dispose() {
    // Avoid memory leak (`setState` after dispose) and disconnect
    if (_connection != null) {
      print("closing connection");
      _disconnecting = true;
      _connection?.dispose();
      _connection = null;
      _server = null;
    }
  }

  void printMessage(_message msg) {
    print(PidName[msg.whom] + ': ' + msg.text);
  }

  void printReceived() {
    int size = messages.length;

    messages.sublist(0, size).forEach((element) {
      printMessage(element);
    });
    messages.removeRange(0, size);
  }

  _message setValueByMessage(_message msg) {
    int val;

    if (msg.text == "Timeout") {
      val = 0x7fffffff;
    } else {
      val = int.parse(msg.text);
    }
    if (msg.whom == 164) {
      battery_charge = val;
    } else {
      _values[msg.whom] = val;
    }
    return msg;
  }

  void _onDataReceived(Uint8List data) {
    String _rawMessage = '';
    // Allocate buffer for parsed data
    int backspacesCounter = 0;
    data.forEach((byte) {
      if (byte == 8 || byte == 127) {
        backspacesCounter++;
      }
    });
    Uint8List buffer = Uint8List(data.length - backspacesCounter);
    int bufferIndex = buffer.length;

    // Apply backspace control character
    backspacesCounter = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i] == 8 || data[i] == 127) {
        backspacesCounter++;
      } else {
        if (backspacesCounter > 0) {
          backspacesCounter--;
        } else {
          buffer[--bufferIndex] = data[i];
        }
      }
    }

    // Create message if there is new line character
    String dataString = String.fromCharCodes(buffer);
    int index = buffer.indexOf(13);
    if (~index != 0) {
      _rawMessage = backspacesCounter > 0
          ? _messageBuffer.substring(
              0, _messageBuffer.length - backspacesCounter)
          : _messageBuffer + dataString.substring(0, index);
      messages.add(
        setValueByMessage(_message.fromList(_rawMessage.split(":")))
      );
      _messageBuffer = dataString.substring(index);
    } else {
      _messageBuffer = (backspacesCounter > 0
          ? _messageBuffer.substring(
              0, _messageBuffer.length - backspacesCounter)
          : _messageBuffer + dataString);
    }
  }

  void _sendMessage(String text) async {
    text = text.trim();
    // textEditingController.clear();

    if (text.length > 0) {
      try {
        _connection.output.add(Uint8List.fromList(utf8.encode(text + "\r\n")));
        await _connection.output.allSent;
      } catch (e) {
        // Ignore error, but notify state
        print("error: $text");
      }
    }
  }

  get ENG_RPM => _values[OBDPid.ENGINE_SPEED.index];
  get ENG_LOAD => _values[OBDPid.CALCULATED_ENGINE_LOAD.index];
  get COOL_TMP => _values[OBDPid.ENGINE_COOLANT_TEMPERATURE.index];
  get FUEL_LVL => _values[OBDPid.FUEL_TANK_LEVEL_INPUT.index];
  get CUR_SPD => _values[OBDPid.VEHICLE_SPEED.index];
  get ACCEL => _values[OBDPid.THROTTLE_POSITION.index];
  get BAT_CHG => battery_charge;

  get getServer => _server;
  set setServer(BluetoothDevice server) => _server = server;

  get getConnection => _connection;
  set setConnection(BluetoothConnection connection) => _connection = connection;

  get getConnected => _connected;
  set setConnected(bool connected) => _connected = connected;

  get Messages => messages;
  get getMessageBuffer => _messageBuffer;
  set setMessageBuffer(String msgBuf) => _messageBuffer = msgBuf;
}
