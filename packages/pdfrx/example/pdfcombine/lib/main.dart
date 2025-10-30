import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
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

/// Represents a single page item in the page list with its source document info
class PageItem {
  PageItem({
    required this.documentId,
    required this.documentName,
    required this.pageIndex,
    required this.page,
  });

  final String documentId; // Unique ID for the source document
  final String documentName; // Original file name
  final int pageIndex; // Original page index in source document
  final PdfPage page;
}

/// Manages loaded PDF documents and tracks page usage
class DocumentManager {
  final Map<String, PdfDocument> _documents = {};
  final Map<String, String> _documentNames = {};
  final Map<String, int> _pageRefCounts = {};
  int _nextDocId = 0;

  /// Loads a PDF document and returns its ID
  Future<String> loadDocument(String name, String filePath) async {
    final docId = 'doc_${_nextDocId++}';
    final doc = await PdfDocument.openFile(filePath);
    _documents[docId] = doc;
    _documentNames[docId] = name;
    _pageRefCounts[docId] = 0;
    return docId;
  }

  /// Gets document by ID
  PdfDocument? getDocument(String docId) => _documents[docId];

  /// Gets document name by ID
  String? getDocumentName(String docId) => _documentNames[docId];

  /// Increments reference count for a document's page
  void addPageReference(String docId) {
    _pageRefCounts[docId] = (_pageRefCounts[docId] ?? 0) + 1;
  }

  /// Decrements reference count and disposes document if no pages remain
  void removePageReference(String docId) {
    final count = (_pageRefCounts[docId] ?? 1) - 1;
    _pageRefCounts[docId] = count;

    if (count <= 0) {
      _disposeDocument(docId);
    }
  }

  void _disposeDocument(String docId) {
    _documents[docId]?.dispose();
    _documents.remove(docId);
    _documentNames.remove(docId);
    _pageRefCounts.remove(docId);
  }

  /// Disposes all documents
  void disposeAll() {
    for (final doc in _documents.values) {
      doc.dispose();
    }
    _documents.clear();
    _documentNames.clear();
    _pageRefCounts.clear();
  }
}

/// First page: Page arrangement UI
class PdfCombinePage extends StatefulWidget {
  const PdfCombinePage({super.key});

  @override
  State<PdfCombinePage> createState() => _PdfCombinePageState();
}

class _PdfCombinePageState extends State<PdfCombinePage> {
  final DocumentManager _docManager = DocumentManager();
  final List<PageItem> _pages = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _docManager.disposeAll();
    super.dispose();
  }

  Future<void> _pickPdfFiles() async {
    const typeGroup = XTypeGroup(label: 'PDFs', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);

    if (files.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      for (final file in files) {
        final docId = await _docManager.loadDocument(file.name, file.path);
        final doc = _docManager.getDocument(docId);

        if (doc != null) {
          // Add all pages from this document
          for (var i = 0; i < doc.pages.length; i++) {
            _docManager.addPageReference(docId);
            _pages.add(
              PageItem(
                documentId: docId,
                documentName: file.name,
                pageIndex: i,
                page: doc.pages[i],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _removePage(int index) {
    setState(() {
      final pageItem = _pages[index];
      _pages.removeAt(index);
      _docManager.removePageReference(pageItem.documentId);
    });
  }

  void _onReorder(List<PageItem> Function(List<PageItem>) reorderFunction) {
    setState(() {
      _pages.clear();
      _pages.addAll(reorderFunction(_pages));
    });
  }

  Future<void> _navigateToPreview() async {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add some pages first')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => OutputPreviewPage(pages: _pages)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Combine - Arrange Pages'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickPdfFiles,
            tooltip: 'Add PDF files',
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _pages.isEmpty ? null : _navigateToPreview,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Preview & Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pages.isEmpty
          ? const Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'No pages added.\n'),
                    TextSpan(text: 'Tap the ++++ button to add PDF files.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            )
          : ReorderableBuilder<PageItem>(
              onReorder: _onReorder,
              children: List.generate(_pages.length, (index) {
                final pageItem = _pages[index];
                return CustomDraggable(
                  key: ValueKey(
                    '${pageItem.documentId}_${pageItem.pageIndex}_$index',
                  ),
                  child: _PageThumbnail(
                    page: pageItem.page,
                    onRemove: () => _removePage(index),
                  ),
                );
              }),
              builder: (children) {
                return GridView(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  children: children,
                );
              },
            ),
    );
  }
}

/// Widget for displaying a page thumbnail in the grid
class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({required this.page, required this.onRemove});

  final PdfPage page;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PdfPageView(document: page.document, pageNumber: page.pageNumber),
          // Delete button
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Second page: Output preview and save
class OutputPreviewPage extends StatefulWidget {
  const OutputPreviewPage({super.key, required this.pages});

  final List<PageItem> pages;

  @override
  State<OutputPreviewPage> createState() => _OutputPreviewPageState();
}

class _OutputPreviewPageState extends State<OutputPreviewPage> {
  Uint8List? _outputPdfBytes;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      // Create a new document using the first page's document as base
      final firstPageDoc = widget.pages.first.page.document;
      final combinedDoc = firstPageDoc;

      // Set all selected pages
      combinedDoc.pages = widget.pages.map((item) => item.page).toList();

      // Encode to PDF
      final bytes = await combinedDoc.encodePdf();

      if (mounted) {
        setState(() {
          _outputPdfBytes = bytes;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    }
  }

  Future<void> _savePdf() async {
    if (_outputPdfBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF not ready yet')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Combine - Preview'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          FilledButton.icon(
            onPressed: _outputPdfBytes == null ? null : _savePdf,
            icon: const Icon(Icons.save),
            label: const Text('Save PDF'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating combined PDF...'),
                ],
              ),
            )
          : _outputPdfBytes == null
          ? const Center(child: Text('Failed to generate PDF'))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Combined ${widget.pages.length} pages. Review the PDF below, then save or go back to make changes.',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PdfViewer.data(
                    _outputPdfBytes!,
                    sourceName: 'combined.pdf',
                  ),
                ),
              ],
            ),
    );
  }
}
