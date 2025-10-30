import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import 'save_helper.dart';

void main() {
  pdfrxFlutterInitialize();
  runApp(const PdfCombineApp());
}

class PdfCombineApp extends StatelessWidget {
  const PdfCombineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Combine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PdfCombinePage(),
    );
  }
}

class InputPdfDocument {
  InputPdfDocument(this.name, this.filePath);

  final String name;
  final String filePath;
  late final Future<PdfDocument> documentFuture = PdfDocument.openFile(
    filePath,
  );
  List<int> selectedPages = [];
}

class PdfCombinePage extends StatefulWidget {
  const PdfCombinePage({super.key});

  @override
  State<PdfCombinePage> createState() => _PdfCombinePageState();
}

class _PdfCombinePageState extends State<PdfCombinePage> {
  final List<InputPdfDocument> _inputDocuments = [];
  Uint8List? _outputPdfBytes;
  InputPdfDocument? _selectedDocument;

  Future<void> _pickPdfFiles() async {
    const typeGroup = XTypeGroup(label: 'PDFs', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    if (files.isNotEmpty) {
      setState(() {
        for (final file in files) {
          _inputDocuments.add(InputPdfDocument(file.name, file.path));
        }
      });
    }
  }

  Future<void> _combinePdfs() async {
    if (_inputDocuments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add PDF files first')),
        );
      }
      return;
    }

    try {
      // Load first document to use as the base
      final firstDoc = _inputDocuments.first;
      final PdfDocument combinedDoc = await firstDoc.documentFuture;

      // Build list of pages to include
      final List<PdfPage> combinedPages = [];

      for (final inputDoc in _inputDocuments) {
        final doc = await inputDoc.documentFuture;

        // Get selected pages or all pages if none selected
        final pagesToInclude = inputDoc.selectedPages.isEmpty
            ? List.generate(doc.pages.length, (i) => i)
            : inputDoc.selectedPages;

        for (final pageIndex in pagesToInclude) {
          combinedPages.add(doc.pages[pageIndex]);
        }
      }

      // Update the pages
      combinedDoc.pages = List<PdfPage>.from(combinedPages);

      // Encode to PDF
      final bytes = await combinedDoc.encodePdf();

      if (mounted) {
        setState(() {
          _outputPdfBytes = bytes;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Combined ${combinedPages.length} pages successfully!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error combining PDFs: $e')));
      }
    }
  }

  Future<void> _savePdf() async {
    if (_outputPdfBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please combine PDFs first')),
      );
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'combined_$timestamp.pdf';

      if (kIsWeb) {
        // On Web, use share_plus to trigger browser download
        final xFile = XFile.fromData(
          _outputPdfBytes!,
          name: fileName,
          mimeType: 'application/pdf',
        );
        await Share.shareXFiles([xFile]);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PDF download started')));
        }
      } else {
        // On desktop, use file_selector to save
        final savePath = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'PDF', extensions: ['pdf']),
          ],
        );

        if (savePath != null) {
          await savePdfToFile(savePath.path, _outputPdfBytes!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF saved to: ${savePath.path}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving PDF: $e')));
      }
    }
  }

  void _removeDocument(int index) {
    setState(() {
      _inputDocuments.removeAt(index);
      if (_selectedDocument == _inputDocuments.elementAtOrNull(index)) {
        _selectedDocument = null;
      }
    });
  }

  void _selectDocument(InputPdfDocument doc) {
    setState(() {
      _selectedDocument = doc;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Combine'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickPdfFiles,
            tooltip: 'Add PDF files',
          ),
          IconButton(
            icon: const Icon(Icons.merge_type),
            onPressed: _combinePdfs,
            tooltip: 'Combine PDFs',
          ),
          if (_outputPdfBytes != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _savePdf,
              tooltip: 'Save combined PDF',
            ),
        ],
      ),
      body: Row(
        children: [
          // Left panel: Input documents list
          SizedBox(
            width: 250,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Input PDFs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: _inputDocuments.isEmpty
                      ? const Center(
                          child: Text(
                            'No PDFs added\nClick + to add files',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _inputDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = _inputDocuments[index];
                            final isSelected = _selectedDocument == doc;
                            return Card(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              child: ListTile(
                                title: Text(
                                  doc.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: FutureBuilder<PdfDocument>(
                                  future: doc.documentFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      final pageCount =
                                          snapshot.data!.pages.length;
                                      final selectedCount =
                                          doc.selectedPages.isEmpty
                                          ? pageCount
                                          : doc.selectedPages.length;
                                      return Text(
                                        '$selectedCount / $pageCount pages',
                                      );
                                    }
                                    return const Text('Loading...');
                                  },
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _removeDocument(index),
                                ),
                                onTap: () => _selectDocument(doc),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Middle panel: Page selection
          Expanded(
            flex: 2,
            child: _selectedDocument == null
                ? const Center(child: Text('Select a PDF to choose pages'))
                : PageSelectionPanel(
                    document: _selectedDocument!,
                    onPagesChanged: (pages) {
                      setState(() {
                        _selectedDocument!.selectedPages = pages;
                      });
                    },
                  ),
          ),
          const VerticalDivider(width: 1),
          // Right panel: Output preview
          Expanded(
            flex: 2,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Combined PDF Preview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: _outputPdfBytes == null
                      ? const Center(
                          child: Text(
                            'No combined PDF yet\nClick merge to combine',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : PdfViewer.data(
                          _outputPdfBytes!,
                          sourceName: 'combined.pdf',
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PageSelectionPanel extends StatefulWidget {
  const PageSelectionPanel({
    super.key,
    required this.document,
    required this.onPagesChanged,
  });

  final InputPdfDocument document;
  final ValueChanged<List<int>> onPagesChanged;

  @override
  State<PageSelectionPanel> createState() => _PageSelectionPanelState();
}

class _PageSelectionPanelState extends State<PageSelectionPanel> {
  late Set<int> _selectedPages;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _selectedPages = Set<int>.from(widget.document.selectedPages);
  }

  @override
  void didUpdateWidget(PageSelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _selectedPages = Set<int>.from(widget.document.selectedPages);
      _selectAll = false;
    }
  }

  void _togglePage(int pageIndex) {
    setState(() {
      if (_selectedPages.contains(pageIndex)) {
        _selectedPages.remove(pageIndex);
      } else {
        _selectedPages.add(pageIndex);
      }
      widget.onPagesChanged(_selectedPages.toList()..sort());
    });
  }

  void _toggleSelectAll(int totalPages) {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedPages = Set<int>.from(List.generate(totalPages, (i) => i));
      } else {
        _selectedPages.clear();
      }
      widget.onPagesChanged(_selectedPages.toList()..sort());
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PdfDocument>(
      future: widget.document.documentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No document'));
        }

        final doc = snapshot.data!;
        final pageCount = doc.pages.length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Text(
                    'Select Pages (${_selectedPages.length}/$pageCount)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _toggleSelectAll(pageCount),
                    icon: Icon(_selectAll ? Icons.deselect : Icons.select_all),
                    label: Text(_selectAll ? 'Deselect All' : 'Select All'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8.0),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: pageCount,
                itemBuilder: (context, index) {
                  final isSelected = _selectedPages.contains(index);
                  final page = doc.pages[index];
                  return GestureDetector(
                    onTap: () => _togglePage(index),
                    child: Card(
                      elevation: isSelected ? 8 : 2,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Container(
                                  color: Colors.white,
                                  margin: const EdgeInsets.all(4),
                                  child: FutureBuilder<PdfImage?>(
                                    future: page.render(
                                      fullWidth: page.width * 2,
                                      fullHeight: page.height * 2,
                                    ),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        final image = snapshot.data!;
                                        return Image.memory(
                                          image.pixels,
                                          width: image.width.toDouble(),
                                          height: image.height.toDouble(),
                                          fit: BoxFit.contain,
                                        );
                                      }
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: CircleAvatar(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      radius: 16,
                                      child: const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              'Page ${index + 1}',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
