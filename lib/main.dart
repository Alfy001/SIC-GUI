import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: AssemblerScreen(),
    );
  }
}

class AssemblerScreen extends StatefulWidget {
  const AssemblerScreen({super.key});

  @override
  _AssemblerScreenState createState() => _AssemblerScreenState();
}

class _AssemblerScreenState extends State<AssemblerScreen> {
  TextEditingController inputController = TextEditingController();
  TextEditingController optabController = TextEditingController();
  TextEditingController intermediateController = TextEditingController();
  TextEditingController symtabController = TextEditingController();
  TextEditingController opcodeController = TextEditingController();

  final _dialogTitleController = TextEditingController();
  final _initialDirectoryController = TextEditingController();

  List<PlatformFile>? _paths;
  String? _extension;
  bool _lockParentWindow = false;
  bool _multiPick = false;
  FileType _pickingType = FileType.any;

  Future<void> pickFile(TextEditingController controller) async {
    try {
      _paths = (await FilePicker.platform.pickFiles(
        type: _pickingType,
        allowMultiple: _multiPick,
        onFileLoading: (FilePickerStatus status) => print(status),
        allowedExtensions: (_extension?.isNotEmpty ?? false)
            ? _extension?.replaceAll(' ', '').split(',')
            : null,
        dialogTitle: _dialogTitleController.text,
        initialDirectory: _initialDirectoryController.text,
        lockParentWindow: _lockParentWindow,
      ))
          ?.files;
      if (_paths != null) {
        if (_paths != null && _paths!.isNotEmpty &&
            _paths!.first.path != null) {
          File file = File(
              _paths!.first.path!);
          Uint8List fileData = await file.readAsBytes();
          controller.text = String.fromCharCodes(fileData);
        } else {
          print("No file selected");
        };
      }
    } on PlatformException catch (e) {
      print('Unsupported operation' + e.toString());
    } catch (e) {
      print(e);
    }
  }


  void processAssembler(String inputContent, String optabContent) {
    final inputLines = inputContent.split("\n");
    final optabLines = optabContent.split("\n");

    Map<String, String> OPTAB = {};
    for (var line in optabLines) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        OPTAB[parts[0]] = parts[1];
      }
    }

    Map<String, int> SYMTAB = {};
    int LOCCTR = 0;
    String intermediateContent = "";
    String symtabContent = "";
    int startAddress = 0;
    String programName = "";
    int programLength = 0;

    for (var line in inputLines) {
      final parts = line.split(RegExp(r'\s+'));
      final label = parts.isNotEmpty ? parts[0] : '';
      final opcode = parts.length > 1 ? parts[1] : '';
      final operand = parts.length > 2 ? parts[2] : '';

      if (opcode == "START") {
        startAddress = int.parse(operand, radix: 16);
        LOCCTR = startAddress;
        programName = label;
        intermediateContent += "\t$line\n";
      } else if (opcode == "END") {
        intermediateContent += "${LOCCTR.toRadixString(16)}\t$line\n";
        programLength = LOCCTR - startAddress;
      } else {
        intermediateContent +=
        "${LOCCTR.toRadixString(16).padLeft(4, '0')}\t$line\n";

        if (label.isNotEmpty && label != "-") {
          if (SYMTAB.containsKey(label)) {
            print("Error: Symbol $label already exists in SYMTAB.");
          } else {
            SYMTAB[label] = LOCCTR;
            symtabContent +=
            "$label\t${LOCCTR.toRadixString(16).padLeft(4, '0')}\n";
          }
        }

        if (OPTAB.containsKey(opcode)) {
          LOCCTR += 3;
        } else if (opcode == "WORD") {
          LOCCTR += 3;
        } else if (opcode == "RESW") {
          LOCCTR += 3 * int.parse(operand);
        } else if (opcode == "RESB") {
          LOCCTR += int.parse(operand);
        } else if (opcode == "BYTE") {
          LOCCTR += operand.length - 3;
        }
      }
    }

    String objectCodeContent = "";
    String outputContent = "";
    final intermediateLines = intermediateContent.split("\n");
    LOCCTR = startAddress;

    String headerRecord =
        "H^${programName.padRight(6)}^${startAddress.toRadixString(16).padLeft(
        6, '0')}^${programLength.toRadixString(16).padLeft(6, '0')}\n";
    String textRecord = "";
    String textStartAddress = LOCCTR.toRadixString(16).padLeft(6, "0");
    List<String> textRecordBuffer = [];
    int textRecordLength = 0;

    for (var intermediateLine in intermediateLines) {
      final lineParts = intermediateLine.split("\t");
      final currentLOCCTR = lineParts[0];
      final originalLine = lineParts.sublist(1).join("\t").trim();
      final parts = originalLine.split(RegExp(r'\s+'));
      final label = parts.isNotEmpty ? parts[0] : '';
      final opcode = parts.length > 1 ? parts[1] : '';
      final operand = parts.length > 2 ? parts[2] : '';

      if (opcode == "START") {
        outputContent += "\t$originalLine\n";
      } else if (OPTAB.containsKey(opcode)) {
        String objCode = OPTAB[opcode]!;
        String address = "0000";

        if (operand.isNotEmpty && SYMTAB.containsKey(operand)) {
          address = SYMTAB[operand]!.toRadixString(16).padLeft(4, "0");
        }

        String fullObjectCode = "$objCode$address";
        textRecordBuffer.add(fullObjectCode);
        textRecordLength += 3;

        objectCodeContent += "$currentLOCCTR\t$fullObjectCode\n";
        outputContent += "$currentLOCCTR\t$originalLine\t$fullObjectCode\n";

        if (textRecordLength >= 30) {
          textRecord +=
          "T^$textStartAddress^${textRecordLength.toRadixString(16).padLeft(
              2, '0')}^${textRecordBuffer.join('^')}\n";
          textStartAddress = LOCCTR.toRadixString(16).padLeft(6, "0");
          textRecordBuffer = [];
          textRecordLength = 0;
        }
      } else if (opcode == "WORD") {
        final wordValue = int.parse(operand).toRadixString(16).padLeft(6, "0");
        textRecordBuffer.add(wordValue);
        textRecordLength += 3;

        objectCodeContent += "$currentLOCCTR\t$wordValue\n";
        outputContent += "$currentLOCCTR\t$originalLine\t$wordValue\n";
      } else if (opcode == "BYTE") {
        String byteValue = operand.substring(2, operand.length - 1);
        if (operand.startsWith("C'")) {
          byteValue = byteValue
              .split("")
              .map((char) => char.codeUnitAt(0).toRadixString(16))
              .join("");
        } else if (operand.startsWith("X'")) {
          byteValue = byteValue.toUpperCase();
        }
        textRecordBuffer.add(byteValue);
        textRecordLength += byteValue.length ~/ 2;

        objectCodeContent += "$currentLOCCTR\t$byteValue\n";
        outputContent += "$currentLOCCTR\t$originalLine\t$byteValue\n";
      } else if (opcode == "RESW" || opcode == "RESB") {
        outputContent += "$currentLOCCTR\t$originalLine\n";
      }

      if (opcode == "END") {
        if (textRecordBuffer.isNotEmpty) {
          textRecord +=
          "T^$textStartAddress^${textRecordLength.toRadixString(16).padLeft(
              2, '0')}^${textRecordBuffer.join('^')}\n";
        }
        outputContent += "$currentLOCCTR\t$originalLine\n";
      }
    }

    String endRecord = "E^${startAddress.toRadixString(16).padLeft(6, '0')}\n";
    objectCodeContent = headerRecord + textRecord + endRecord;

    setState(() {
      intermediateController.text = intermediateContent;
      symtabController.text = symtabContent;
      opcodeController.text = objectCodeContent;
    });
  }

  void reset() {
    setState(() {
      inputController.clear();
      optabController.clear();
      intermediateController.clear();
      symtabController.clear();
      opcodeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assembler Processor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: inputController,
                decoration: InputDecoration(
                  labelText: 'Input File Content',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => pickFile(inputController),
                  ),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: optabController,
                decoration: InputDecoration(
                  labelText: 'Optab File Content',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => pickFile(optabController),
                  ),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      processAssembler(
                          inputController.text, optabController.text);
                    },
                    child: const Text('Process'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: intermediateController,
                decoration: const InputDecoration(
                    labelText: 'Intermediate Output'),
                maxLines: 5,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: symtabController,
                decoration: const InputDecoration(labelText: 'Symtab Output'),
                maxLines: 5,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: opcodeController,
                decoration: const InputDecoration(labelText: 'Opcode Output'),
                maxLines: 5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
