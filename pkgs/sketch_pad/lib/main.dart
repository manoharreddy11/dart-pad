// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dartpad_shared/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart' show usePathUrlStrategy;
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:split_view/split_view.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:vtable/vtable.dart';

import 'console.dart';
import 'editor/editor.dart';
import 'execution/execution.dart';
import 'extensions.dart';
import 'keys.dart' as keys;
import 'model.dart';
import 'problems.dart';
import 'samples.g.dart';
import 'theme.dart';
import 'utils.dart';
import 'versions.dart';
import 'widgets.dart';

// TODO: show documentation on hover

// TODO: implement find / find next

const appName = 'DartPad';
const smallScreenWidth = 720;

void main() async {
  usePathUrlStrategy();
  runApp(const DartPadApp());
}

class DartPadApp extends StatefulWidget {
  const DartPadApp({
    super.key,
  });

  @override
  State<DartPadApp> createState() => _DartPadAppState();
}

class _DartPadAppState extends State<DartPadApp> {
  late final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: _homePageBuilder,
      ),
    ],
  );

  ThemeMode themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();

    router.routeInformationProvider.addListener(_setTheme);
    _setTheme();
  }

  @override
  void dispose() {
    router.routeInformationProvider.removeListener(_setTheme);

    super.dispose();
  }

  // Changes the `themeMode` from the system default to either light or dark.
  // Also changes the `theme` query parameter in the URL.
  void handleBrightnessChanged(BuildContext context, bool isLightMode) {
    if (isLightMode) {
      GoRouter.of(context).replaceQueryParam('theme', 'light');
    } else {
      GoRouter.of(context).replaceQueryParam('theme', 'dark');
    }
    _setTheme();
  }

  void _setTheme() {
    final params = router.routeInformationProvider.value.uri.queryParameters;
    final themeParam = params.containsKey('theme') ? params['theme'] : null;

    setState(() {
      switch (themeParam) {
        case 'dark':
          setState(() {
            themeMode = ThemeMode.dark;
          });
        case 'light':
          setState(() {
            themeMode = ThemeMode.light;
          });
        case _:
          setState(() {
            themeMode = ThemeMode.dark;
          });
      }
    });
  }

  Widget _homePageBuilder(BuildContext context, GoRouterState state) {
    final gistId = state.uri.queryParameters['id'];
    final builtinSampleId = state.uri.queryParameters['sample'];
    final flutterSampleId = state.uri.queryParameters['sample_id'];
    final channelParam = state.uri.queryParameters['channel'];
    final embedMode = state.uri.queryParameters['embed'] == 'true';
    final runOnLoad = state.uri.queryParameters['run'] == 'true';

    return DartPadMainPage(
      title: appName,
      initialChannel: channelParam,
      embedMode: embedMode,
      runOnLoad: runOnLoad,
      gistId: gistId,
      builtinSampleId: builtinSampleId,
      flutterSampleId: flutterSampleId,
      handleBrightnessChanged: handleBrightnessChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: appName,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: lightPrimaryColor).copyWith(
          surface: lightSurfaceColor,
          onSurface: Colors.black,
          // TODO: Migrate to expanded Material 3 color palette.
          // ignore: deprecated_member_use
          surfaceVariant: lightSurfaceVariantColor,
          onPrimary: lightLinkButtonColor,
        ),
        brightness: Brightness.light,
        dividerColor: lightDividerColor,
        dividerTheme: DividerThemeData(
          color: lightDividerColor,
        ),
        scaffoldBackgroundColor: Colors.white,
        menuButtonTheme: MenuButtonThemeData(
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: darkPrimaryColor).copyWith(
          brightness: Brightness.dark,
          surface: darkSurfaceColor,
          onSurface: Colors.white,
          // TODO: Migrate to expanded Material 3 color palette.
          // ignore: deprecated_member_use
          surfaceVariant: darkSurfaceVariantColor,
          onSurfaceVariant: Colors.white,
          onPrimary: darkLinkButtonColor,
        ),
        brightness: Brightness.dark,
        dividerColor: darkDividerColor,
        dividerTheme: DividerThemeData(
          color: darkDividerColor,
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: MaterialStatePropertyAll(darkLinkButtonColor),
          ),
        ),
        scaffoldBackgroundColor: darkScaffoldColor,
        menuButtonTheme: MenuButtonThemeData(
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      ),
    );
  }
}

class DartPadMainPage extends StatefulWidget {
  final String title;
  final String? initialChannel;
  final bool embedMode;
  final bool runOnLoad;
  final void Function(BuildContext, bool) handleBrightnessChanged;
  final String? gistId;
  final String? builtinSampleId;
  final String? flutterSampleId;

  DartPadMainPage({
    required this.title,
    required this.initialChannel,
    required this.embedMode,
    required this.runOnLoad,
    required this.handleBrightnessChanged,
    this.gistId,
    this.builtinSampleId,
    this.flutterSampleId,
  }) : super(
          key: ValueKey(
            'sample:$builtinSampleId gist:$gistId flutter:$flutterSampleId',
          ),
        );

  @override
  State<DartPadMainPage> createState() => _DartPadMainPageState();
}

class _DartPadMainPageState extends State<DartPadMainPage>
    with SingleTickerProviderStateMixin {
  late final SplitViewController mainSplitter;

  late AppModel appModel;
  late AppServices appServices;
  late final TabController tabController;
  final ValueKey<String> _executionWidgetKey =
      const ValueKey('execution-widget');
  final ValueKey<String> _loadingOverlayKey =
      const ValueKey('loading-overlay-widget');
  final ValueKey<String> _editorKey = const ValueKey('editor');
  final ValueKey<String> _consoleKey = const ValueKey('console');

  @override
  void initState() {
    super.initState();

    tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        // Rebuild when the user changes tabs so that the IndexedStack updates
        // its active child view.
        setState(() {});
      });
    final leftPanelSize = widget.embedMode ? 0.62 : 0.50;
    mainSplitter =
        SplitViewController(weights: [leftPanelSize, 1.0 - leftPanelSize])
          ..addListener(() {
            appModel.splitDragStateManager.handleSplitChanged();
          });

    final channel = widget.initialChannel != null
        ? Channel.forName(widget.initialChannel!)
        : null;

    appModel = AppModel();
    appServices = AppServices(
      appModel,
      channel ?? Channel.defaultChannel,
    );

    appServices.populateVersions();

    appServices
        .performInitialLoad(
            gistId: widget.gistId,
            sampleId: widget.builtinSampleId,
            flutterSampleId: widget.flutterSampleId,
            channel: widget.initialChannel,
            fallbackSnippet: Samples.getDefault(type: 'dart'))
        .then((value) {
      if (widget.runOnLoad) {
        _performCompileAndRun();
      }
    });
  }

  @override
  void dispose() {
    appServices.dispose();
    appModel.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final executionWidget = ExecutionWidget(
      appServices: appServices,
      appModel: appModel,
      key: _executionWidgetKey,
    );
    final loadingOverlay = LoadingOverlay(
      appModel: appModel,
      key: _loadingOverlayKey,
    );
    final editor = EditorWithButtons(
      appModel: appModel,
      appServices: appServices,
      onFormat: _handleFormatting,
      onCompileAndRun: _performCompileAndRun,
      key: _editorKey,
    );

    consoleWidget({bool showDivider = false}) => ConsoleWidget(
          textController: appModel.consoleOutputController,
          showDivider: showDivider,
          key: _consoleKey,
        );
    final scaffold =
        LayoutBuilder(builder: (context, BoxConstraints constraints) {
      // Use the mobile UI layout for small screen widths.
      if (constraints.maxWidth <= smallScreenWidth) {
        return Scaffold(
          appBar: widget.embedMode
              ? TabBar(
                  controller: tabController,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.code),
                      child: Semantics(
                        label: 'Dart Code',
                        child: const Text('Code'),
                      ),
                    ),
                    Tab(
                      icon: const Icon(Icons.phone_android),
                      child: Semantics(
                        label: 'UI Output',
                        child: const Text('UI Output'),
                      ),
                    ),
                    Tab(
                      icon: const Icon(Icons.terminal),
                      child: Semantics(
                        label: 'Console Output',
                        child: const Text('Console Output'),
                      ),
                    ),
                  ],
                )
              : DartPadAppBar(
                  theme: theme,
                  appServices: appServices,
                  appModel: appModel,
                  widget: widget,
                  bottom: TabBar(
                    controller: tabController,
                    tabs: const [
                      Tab(icon: Icon(Icons.code)),
                      Tab(icon: Icon(Icons.phone_android)),
                      Tab(icon: Icon(Icons.terminal)),
                    ],
                  ),
                ),
          body: IndexedStack(
            index: tabController.index,
            children: [
              editor,
              executionWidget,
              consoleWidget(),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: widget.embedMode
            ? null
            : DartPadAppBar(
                theme: theme,
                appServices: appServices,
                appModel: appModel,
                widget: widget,
              ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: SplitView(
                  viewMode: SplitViewMode.Horizontal,
                  gripColor: theme.colorScheme.surface,
                  gripColorActive: theme.colorScheme.surface,
                  gripSize: defaultGripSize,
                  controller: mainSplitter,
                  children: [
                    editor,
                    Stack(
                      children: [
                        ValueListenableBuilder(
                          valueListenable: appModel.layoutMode,
                          builder: (context, LayoutMode mode, _) {
                            return LayoutBuilder(
                              builder: (BuildContext context,
                                  BoxConstraints constraints) {
                                final domHeight =
                                    mode.calcDomHeight(constraints.maxHeight);
                                final consoleHeight = mode
                                    .calcConsoleHeight(constraints.maxHeight);

                                return Column(
                                  children: [
                                    SizedBox(
                                      height: domHeight,
                                      child: executionWidget,
                                    ),
                                    SizedBox(
                                      height: consoleHeight,
                                      child: consoleWidget(
                                          showDivider: mode == LayoutMode.both),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        loadingOverlay,
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!widget.embedMode) const StatusLineWidget(),
          ],
        ),
      );
    });

    return Provider<AppServices>.value(
      value: appServices,
      child: Provider<AppModel>.value(
        value: appModel,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            keys.reloadKeyActivator: () {
              if (!appModel.compilingBusy.value) {
                _performCompileAndRun();
              }
            },
            keys.findKeyActivator: () {
              // TODO:
              unimplemented(context, 'find');
            },
            keys.findNextKeyActivator: () {
              // TODO:
              unimplemented(context, 'find next');
            },
            keys.codeCompletionKeyActivator: () {
              appServices.editorService?.showCompletions();
            },
            keys.quickFixKeyActivator: () {
              appServices.editorService?.showQuickFixes();
            },
          },
          child: Focus(
            autofocus: true,
            child: scaffold,
          ),
        ),
      ),
    );
  }

  Future<void> _handleFormatting() async {
    try {
      final value = appModel.sourceCodeController.text;
      final result = await appServices.format(SourceRequest(source: value));

      if (result.source == value) {
        appModel.editorStatus.showToast('No formatting changes');
      } else {
        appModel.editorStatus.showToast('Format successful');
        appModel.sourceCodeController.text = result.source;
      }
    } catch (error) {
      appModel.editorStatus.showToast('Error formatting code');
      appModel.appendLineToConsole('Formatting issue: $error');
      return;
    }
  }

  Future<void> _performCompileAndRun() async {
    final source = appModel.sourceCodeController.text;
    final progress =
        appModel.editorStatus.showMessage(initialText: 'Compiling…');

    try {
      final response =
          await appServices.compileDDC(CompileRequest(source: source));
      appModel.clearConsole();
      appServices.executeJavaScript(
        response.result,
        modulesBaseUrl: response.modulesBaseUrl,
        engineVersion: appModel.runtimeVersions.value?.engineVersion,
        dartSource: source,
      );
    } catch (error) {
      appModel.clearConsole();

      appModel.editorStatus.showToast('Compilation failed');

      if (error is ApiRequestError) {
        appModel.appendLineToConsole(error.message);
        appModel.appendLineToConsole(error.body);
      } else {
        appModel.appendLineToConsole('$error');
      }
    } finally {
      progress.close();
    }
  }
}

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.appModel,
  });

  final AppModel appModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: appModel.compilingBusy,
      builder: (_, bool compiling, __) {
        final color = theme.colorScheme.surface;

        return AnimatedContainer(
          color: compiling ? color.withOpacity(0.8) : color.withOpacity(0.0),
          duration: animationDelay,
          curve: animationCurve,
          child: compiling
              ? const GoldenRatioCenter(
                  child: CircularProgressIndicator(),
                )
              : const SizedBox(width: 1),
        );
      },
    );
  }
}

class DartPadAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DartPadAppBar({
    super.key,
    required this.theme,
    required this.appServices,
    required this.appModel,
    required this.widget,
    this.bottom,
  });

  final ThemeData theme;
  final AppServices appServices;
  final AppModel appModel;
  final DartPadMainPage widget;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return AppBar(
        backgroundColor: theme.colorScheme.surface,
        bottom: bottom,
        title: SizedBox(
          height: toolbarItemHeight,
          child: Row(
            children: [
              const Logo(width: 32, type: 'dart'),
              const SizedBox(width: denseSpacing),
              Text(appName,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface)),
              // Hide new snippet buttons when the screen width is too small.
              if (constraints.maxWidth > smallScreenWidth) ...[
                const SizedBox(width: defaultSpacing * 4),
                NewSnippetWidget(appServices: appServices),
                const SizedBox(width: denseSpacing),
                const ListSamplesWidget(),
              ] else ...[
                const SizedBox(width: defaultSpacing),
                NewSnippetWidget(appServices: appServices, smallIcon: true),
                const SizedBox(width: defaultSpacing),
                const ListSamplesWidget(smallIcon: true),
              ],

              const SizedBox(width: defaultSpacing),
              // Hide the snippet title when the screen width is too small.
              if (constraints.maxWidth > smallScreenWidth)
                Expanded(
                  child: Center(
                    child: ValueListenableBuilder<String>(
                      valueListenable: appModel.title,
                      builder: (_, String value, __) => Text(value),
                    ),
                  ),
                ),
              const SizedBox(width: defaultSpacing),
            ],
          ),
        ),
        actions: [
          // Hide the Install SDK button when the screen width is too small.
          if (constraints.maxWidth > smallScreenWidth)
            TextButton(
              onPressed: () {
                url_launcher.launchUrl(
                  Uri.parse('https://docs.flutter.dev/get-started/install'),
                );
              },
              child: const Row(
                children: [
                  Text('Install SDK'),
                  SizedBox(width: denseSpacing),
                  Icon(Icons.launch, size: 18),
                ],
              ),
            ),
          const SizedBox(width: denseSpacing),
          _BrightnessButton(
            handleBrightnessChange: widget.handleBrightnessChanged,
          ),
          const OverflowMenu(),
        ],
      );
    });
  }

  @override
  // kToolbarHeight is set to 56.0 in the framework.
  Size get preferredSize => bottom == null
      ? const Size(double.infinity, 56.0)
      : const Size(double.infinity, 112.0);
}

class EditorWithButtons extends StatelessWidget {
  const EditorWithButtons({
    super.key,
    required this.appModel,
    required this.appServices,
    required this.onFormat,
    required this.onCompileAndRun,
  });

  final AppModel appModel;
  final AppServices appServices;
  final VoidCallback onFormat;
  final VoidCallback onCompileAndRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SectionWidget(
            child: Stack(
              children: [
                EditorWidget(
                  appModel: appModel,
                  appServices: appServices,
                ),
                Padding(
                  padding: const EdgeInsets.all(denseSpacing),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    // We use explicit directionality here in order to have the
                    // format and run buttons on the right hand side of the
                    // editing area.
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Format action
                      ValueListenableBuilder<bool>(
                        valueListenable: appModel.formattingBusy,
                        builder: (_, bool value, __) {
                          return PointerInterceptor(
                            child: MiniIconButton(
                              icon: Icons.format_align_left,
                              tooltip: 'Format',
                              small: true,
                              onPressed: value ? null : onFormat,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: defaultSpacing),
                      // Run action
                      ValueListenableBuilder<bool>(
                        valueListenable: appModel.compilingBusy,
                        builder: (_, bool value, __) {
                          return PointerInterceptor(
                            child: RunButton(
                              onPressed: value ? null : onCompileAndRun,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Container(
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(denseSpacing),
                  child: StatusWidget(
                    status: appModel.editorStatus,
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<List<AnalysisIssue>>(
          valueListenable: appModel.analysisIssues,
          builder: (context, issues, _) {
            return ProblemsTableWidget(problems: issues);
          },
        ),
      ],
    );
  }
}

class StatusLineWidget extends StatelessWidget {
  const StatusLineWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final appModel = Provider.of<AppModel>(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      padding: const EdgeInsets.symmetric(
        vertical: denseSpacing,
        horizontal: defaultSpacing,
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Keyboard shortcuts',
            waitDuration: tooltipDelay,
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => MediumDialog(
                  title: 'Keyboard shortcuts',
                  smaller: true,
                  child: KeyBindingsTable(bindings: keys.keyBindings),
                ),
              ),
              child: Icon(
                Icons.keyboard,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: defaultSpacing),
          TextButton(
            onPressed: () {
              const url = 'https://dart.dev/tools/dartpad/privacy';
              url_launcher.launchUrl(Uri.parse(url));
            },
            child: const Row(
              children: [
                Text('Privacy notice'),
                SizedBox(width: denseSpacing),
                Icon(Icons.launch, size: 16),
              ],
            ),
          ),
          const SizedBox(width: defaultSpacing),
          TextButton(
            onPressed: () {
              const url = 'https://github.com/dart-lang/dart-pad/issues';
              url_launcher.launchUrl(Uri.parse(url));
            },
            child: const Row(
              children: [
                Text('Feedback'),
                SizedBox(width: denseSpacing),
                Icon(Icons.launch, size: 16),
              ],
            ),
          ),
          const Expanded(child: SizedBox(width: defaultSpacing)),
          VersionInfoWidget(appModel.runtimeVersions),
          const SizedBox(width: defaultSpacing),
          const SizedBox(height: 26, child: SelectChannelWidget()),
        ],
      ),
    );
  }
}

class SectionWidget extends StatelessWidget {
  final String? title;
  final Widget? actions;
  final Widget child;

  const SectionWidget({
    this.title,
    this.actions,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var c = child;

    if (title != null || actions != null) {
      c = Column(
        children: [
          Row(
            children: [
              if (title != null) Text(title!, style: subtleText),
              const Expanded(child: SizedBox(width: defaultSpacing)),
              if (actions != null) actions!,
            ],
          ),
          const Divider(),
          Expanded(child: child),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(denseSpacing),
      child: c,
    );
  }
}

class NewSnippetWidget extends StatelessWidget {
  final AppServices appServices;
  final bool smallIcon;

  static const _menuItems = [
    (
      label: 'Dart snippet',
      icon: Logo(type: 'dart'),
      kind: 'dart',
    ),
    (
      label: 'Flutter snippet',
      icon: Logo(type: 'flutter'),
      kind: 'flutter',
    ),
  ];

  const NewSnippetWidget({
    required this.appServices,
    this.smallIcon = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, MenuController controller, Widget? child) {
        if (smallIcon) {
          return IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () => controller.toggleMenuState(),
          );
        }
        return TextButton.icon(
          onPressed: () => controller.toggleMenuState(),
          icon: const Icon(Icons.add_circle),
          label: const Text('New'),
        );
      },
      menuChildren: [
        for (final item in _menuItems)
          PointerInterceptor(
            child: MenuItemButton(
              leadingIcon: item.icon,
              child: Padding(
                padding: const EdgeInsets.only(right: 32),
                child: Text(item.label),
              ),
              onPressed: () => appServices.resetTo(type: item.kind),
            ),
          )
      ],
    );
  }
}

class ListSamplesWidget extends StatelessWidget {
  final bool smallIcon;
  const ListSamplesWidget({this.smallIcon = false, super.key});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, MenuController controller, Widget? child) {
        if (smallIcon) {
          return IconButton(
            icon: const Icon(Icons.playlist_add_outlined),
            onPressed: () => controller.toggleMenuState(),
          );
        }
        return TextButton.icon(
          onPressed: () => controller.toggleMenuState(),
          icon: const Icon(Icons.playlist_add_outlined),
          label: const Text('Samples'),
        );
      },
      menuChildren: _buildMenuItems(context),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    final menuItems = [
      for (final MapEntry(key: category, value: samples)
          in Samples.categories.entries) ...[
        MenuItemButton(
          onPressed: null,
          child: Text(
            category,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        for (final sample in samples)
          MenuItemButton(
            leadingIcon: Logo(type: sample.icon),
            onPressed: () =>
                GoRouter.of(context).replaceQueryParam('sample', sample.id),
            child: Padding(
              padding: const EdgeInsets.only(right: 32),
              child: Text(sample.name),
            ),
          ),
      ]
    ];

    return menuItems.map((e) => PointerInterceptor(child: e)).toList();
  }
}

class SelectChannelWidget extends StatelessWidget {
  const SelectChannelWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final appServices = Provider.of<AppServices>(context);
    final channels = Channel.valuesWithoutLocalhost;

    return ValueListenableBuilder<Channel>(
      valueListenable: appServices.channel,
      builder: (context, Channel value, _) => MenuAnchor(
        builder: (context, MenuController controller, Widget? child) {
          return TextButton.icon(
            onPressed: () => controller.toggleMenuState(),
            icon: const Icon(Icons.tune, size: smallIconSize),
            label: Text('${value.displayName} channel'),
          );
        },
        menuChildren: [
          for (final channel in channels)
            PointerInterceptor(
              child: MenuItemButton(
                onPressed: () => _onTap(context, channel),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 32, 0),
                  child: Text('${channel.displayName} channel'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, Channel channel) async {
    final appServices = Provider.of<AppServices>(context, listen: false);

    // update the url
    GoRouter.of(context).replaceQueryParam('channel', channel.name);

    final version = await appServices.setChannel(channel);

    appServices.appModel.editorStatus.showToast(
      'Switched to Dart ${version.dartVersion} '
      'and Flutter ${version.flutterVersion}',
    );
  }
}

class OverflowMenu extends StatelessWidget {
  const OverflowMenu({super.key});

  static const _menuItems = [
    (
      label: 'dart.dev',
      uri: 'https://dart.dev',
    ),
    (
      label: 'flutter.dev',
      uri: 'https://flutter.dev',
    ),
    (
      label: 'Sharing guide',
      uri: 'https://github.com/dart-lang/dart-pad/wiki/Sharing-Guide'
    ),
    (
      label: 'DartPad on GitHub',
      uri: 'https://github.com/dart-lang/dart-pad',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, MenuController controller, Widget? child) {
        return IconButton(
          onPressed: () => controller.toggleMenuState(),
          icon: const Icon(Icons.more_vert),
        );
      },
      menuChildren: [
        for (final item in _menuItems)
          PointerInterceptor(
            child: MenuItemButton(
              trailingIcon: const Icon(Icons.launch),
              onPressed: () => _onSelected(context, item.uri),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 32, 0),
                child: Text(item.label),
              ),
            ),
          )
      ],
    );
  }

  void _onSelected(BuildContext context, String uri) {
    url_launcher.launchUrl(Uri.parse(uri));
  }
}

class KeyBindingsTable extends StatelessWidget {
  final List<(String, ShortcutActivator)> bindings;

  const KeyBindingsTable({
    required this.bindings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Expanded(
          child: VTable<(String, ShortcutActivator)>(
            showToolbar: false,
            showHeaders: false,
            startsSorted: true,
            items: bindings,
            columns: [
              VTableColumn(
                label: 'Command',
                width: 100,
                grow: 0.5,
                transformFunction: (binding) => binding.$1,
              ),
              VTableColumn(
                label: 'Keyboard shortcut',
                width: 100,
                grow: 0.5,
                alignment: Alignment.centerRight,
                transformFunction: (binding) =>
                    (binding.$2 as SingleActivator).describe,
                styleFunction: (binding) => subtleText,
                renderFunction: (context, binding, _) {
                  return (binding.$2 as SingleActivator)
                      .renderToWidget(context);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VersionInfoWidget extends StatefulWidget {
  final ValueListenable<VersionResponse?> versions;

  const VersionInfoWidget(
    this.versions, {
    super.key,
  });

  @override
  State<VersionInfoWidget> createState() => _VersionInfoWidgetState();
}

class _VersionInfoWidgetState extends State<VersionInfoWidget> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VersionResponse?>(
      valueListenable: widget.versions,
      builder: (content, versions, _) {
        if (versions == null) {
          return const SizedBox();
        }

        return TextButton(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) {
                return MediumDialog(
                  title: 'Runtime versions',
                  child: VersionTable(version: versions),
                );
              },
            );
          },
          child: Text(versions.label),
        );
      },
    );
  }
}

class _BrightnessButton extends StatelessWidget {
  const _BrightnessButton({
    required this.handleBrightnessChange,
  });

  final void Function(BuildContext, bool) handleBrightnessChange;

  @override
  Widget build(BuildContext context) {
    final isBright = Theme.of(context).brightness == Brightness.light;
    return Tooltip(
      preferBelow: true,
      message: 'Toggle brightness',
      child: IconButton(
        icon: Theme.of(context).brightness == Brightness.light
            ? const Icon(Icons.dark_mode_outlined)
            : const Icon(Icons.light_mode_outlined),
        onPressed: () {
          handleBrightnessChange(context, !isBright);
        },
      ),
    );
  }
}

extension MenuControllerToggleMenu on MenuController {
  void toggleMenuState() {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }
}
