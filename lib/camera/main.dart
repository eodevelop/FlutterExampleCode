// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

///---------------------------------------------------------------------------
/// 메인 카메라 앱 위젯 (앱의 진입점)
///---------------------------------------------------------------------------
class CameraExampleHome extends StatefulWidget {
  /// Default Constructor
  const CameraExampleHome({super.key});

  @override
  State<CameraExampleHome> createState() {
    return _CameraExampleHomeState();
  }
}

///---------------------------------------------------------------------------
/// 카메라 방향에 따른 아이콘 반환
///---------------------------------------------------------------------------
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear; // 후면 카메라
    case CameraLensDirection.front:
      return Icons.camera_front; // 전면 카메라
    case CameraLensDirection.external:
      return Icons.camera; // 외부 카메라
  }
  // This enum is from a different package, so a new value could be added at
  // any time. The example should keep working if that happens.
  // ignore: dead_code
  return Icons.camera;
}

///---------------------------------------------------------------------------
/// 오류 로깅 유틸리티 함수
///---------------------------------------------------------------------------
void _logError(String code, String? message) {
  // ignore: avoid_print
  print('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

///---------------------------------------------------------------------------
/// 카메라 앱의 상태 관리 클래스
///---------------------------------------------------------------------------
class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // 카메라 제어 관련 변수들
  CameraController? controller; // 카메라 컨트롤러
  XFile? imageFile; // 촬영된 이미지 파일
  XFile? videoFile; // 촬영된 비디오 파일
  VideoPlayerController? videoController; // 비디오 플레이어 컨트롤러
  VoidCallback? videoPlayerListener; // 비디오 플레이어 리스너
  bool enableAudio = true; // 오디오 활성화 여부

  // 노출 관련 변수들
  double _minAvailableExposureOffset = 0.0; // 최소 노출 오프셋
  double _maxAvailableExposureOffset = 0.0; // 최대 노출 오프셋
  double _currentExposureOffset = 0.0; // 현재 노출 오프셋

  // UI 애니메이션 컨트롤러들
  late final AnimationController
  _flashModeControlRowAnimationController; // 플래시 모드 UI 애니메이션
  late final CurvedAnimation _flashModeControlRowAnimation;
  late final AnimationController
  _exposureModeControlRowAnimationController; // 노출 모드 UI 애니메이션
  late final CurvedAnimation _exposureModeControlRowAnimation;
  late final AnimationController
  _focusModeControlRowAnimationController; // 포커스 모드 UI 애니메이션
  late final CurvedAnimation _focusModeControlRowAnimation;

  // 줌 관련 변수들
  double _minAvailableZoom = 1.0; // 최소 줌 레벨
  double _maxAvailableZoom = 1.0; // 최대 줌 레벨
  double _currentScale = 1.0; // 현재 줌 스케일
  double _baseScale = 1.0; // 기본 줌 스케일

  // 멀티터치 감지용 (손가락 개수 카운팅)
  int _pointers = 0;

  ///---------------------------------------------------------------------------
  /// 상태 초기화 - 애니메이션 컨트롤러 설정
  ///---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashModeControlRowAnimation = CurvedAnimation(
      parent: _flashModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _exposureModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _exposureModeControlRowAnimation = CurvedAnimation(
      parent: _exposureModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _focusModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusModeControlRowAnimation = CurvedAnimation(
      parent: _focusModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
  }

  ///---------------------------------------------------------------------------
  /// 위젯 폐기 시 리소스 정리
  ///---------------------------------------------------------------------------
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    _flashModeControlRowAnimation.dispose();
    _exposureModeControlRowAnimationController.dispose();
    _exposureModeControlRowAnimation.dispose();
    _focusModeControlRowAnimationController.dispose();
    _focusModeControlRowAnimation.dispose();
    super.dispose();
  }

  ///---------------------------------------------------------------------------
  /// 앱 라이프사이클 상태 변화 처리 (백그라운드, 포그라운드 전환 등)
  ///---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // 카메라 초기화 전에는 아무것도 하지 않음
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    // 앱이 백그라운드로 갈 때는 카메라 리소스 해제
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    }
    // 앱이 다시 포그라운드로 돌아오면 카메라 재초기화
    else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }

  ///---------------------------------------------------------------------------
  /// 메인 UI 빌드 - 카메라 미리보기, 컨트롤 버튼, 썸네일 등 구성
  ///---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera example')),
      body: Column(
        children: <Widget>[
          // 카메라 미리보기 영역 (확장 가능)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color:
                      controller != null && controller!.value.isRecordingVideo
                          ? Colors
                              .redAccent // 녹화 중일 때 빨간색 테두리
                          : Colors.grey, // 일반 상태일 때 회색 테두리
                  width: 3.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(child: _cameraPreviewWidget()), // 카메라 미리보기 위젯
              ),
            ),
          ),
          _captureControlRowWidget(), // 사진/비디오 촬영 컨트롤 버튼
          _modeControlRowWidget(), // 플래시/노출/포커스 모드 컨트롤
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: <Widget>[
                _cameraTogglesRowWidget(), // 카메라 전환 버튼 (전면/후면)
                _thumbnailWidget(), // 촬영된 사진/비디오 썸네일
              ],
            ),
          ),
        ],
      ),
    );
  }

  ///---------------------------------------------------------------------------
  /// 카메라 미리보기 위젯 - 카메라 화면 표시 및 제스처 처리
  ///---------------------------------------------------------------------------
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    // 카메라 초기화 안 된 경우 안내 메시지 표시
    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      // 카메라 미리보기 및 제스처 처리
      return Listener(
        onPointerDown: (_) => _pointers++, // 터치 손가락 개수 증가
        onPointerUp: (_) => _pointers--, // 터치 손가락 개수 감소
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _handleScaleStart, // 핀치 줌 시작
                onScaleUpdate: _handleScaleUpdate, // 핀치 줌 업데이트
                onTapDown: // 화면 탭하여 초점/노출 설정
                    (TapDownDetails details) =>
                        onViewFinderTap(details, constraints),
              );
            },
          ),
        ),
      );
    }
  }

  ///---------------------------------------------------------------------------
  /// 핀치 줌 시작 처리 - 기본 스케일 저장
  ///---------------------------------------------------------------------------
  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  ///---------------------------------------------------------------------------
  /// 핀치 줌 업데이트 처리 - 카메라 줌 레벨 변경
  ///---------------------------------------------------------------------------
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // 두 손가락이 아닌 경우에는 줌 조작 안함
    if (controller == null || _pointers != 2) {
      return;
    }

    // 줌 레벨 계산 및 제한 (최소/최대 범위 내에서)
    _currentScale = (_baseScale * details.scale).clamp(
      _minAvailableZoom,
      _maxAvailableZoom,
    );

    // 카메라 줌 레벨 설정
    await controller!.setZoomLevel(_currentScale);
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    final VideoPlayerController? localVideoController = videoController;

    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (localVideoController == null && imageFile == null)
              Container()
            else
              SizedBox(
                width: 64.0,
                height: 64.0,
                child:
                    (localVideoController == null)
                        ? (
                        // The captured image on the web contains a network-accessible URL
                        // pointing to a location within the browser. It may be displayed
                        // either with Image.network or Image.memory after loading the image
                        // bytes to memory.
                        kIsWeb
                            ? Image.network(imageFile!.path)
                            : Image.file(File(imageFile!.path)))
                        : Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.pink),
                          ),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio:
                                  localVideoController.value.aspectRatio,
                              child: VideoPlayer(localVideoController),
                            ),
                          ),
                        ),
              ),
          ],
        ),
      ),
    );
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget _modeControlRowWidget() {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: Colors.blue,
              onPressed: controller != null ? onFlashModeButtonPressed : null,
            ),
            // The exposure and focus mode are currently not supported on the web.
            ...!kIsWeb
                ? <Widget>[
                  IconButton(
                    icon: const Icon(Icons.exposure),
                    color: Colors.blue,
                    onPressed:
                        controller != null ? onExposureModeButtonPressed : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_center_focus),
                    color: Colors.blue,
                    onPressed:
                        controller != null ? onFocusModeButtonPressed : null,
                  ),
                ]
                : <Widget>[],
            IconButton(
              icon: Icon(enableAudio ? Icons.volume_up : Icons.volume_mute),
              color: Colors.blue,
              onPressed: controller != null ? onAudioModeButtonPressed : null,
            ),
            IconButton(
              icon: Icon(
                controller?.value.isCaptureOrientationLocked ?? false
                    ? Icons.screen_lock_rotation
                    : Icons.screen_rotation,
              ),
              color: Colors.blue,
              onPressed:
                  controller != null
                      ? onCaptureOrientationLockButtonPressed
                      : null,
            ),
          ],
        ),
        _flashModeControlRowWidget(),
        _exposureModeControlRowWidget(),
        _focusModeControlRowWidget(),
      ],
    );
  }

  Widget _flashModeControlRowWidget() {
    return SizeTransition(
      sizeFactor: _flashModeControlRowAnimation,
      child: ClipRect(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_off),
              color:
                  controller?.value.flashMode == FlashMode.off
                      ? Colors.orange
                      : Colors.blue,
              onPressed:
                  controller != null
                      ? () => onSetFlashModeButtonPressed(FlashMode.off)
                      : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_auto),
              color:
                  controller?.value.flashMode == FlashMode.auto
                      ? Colors.orange
                      : Colors.blue,
              onPressed:
                  controller != null
                      ? () => onSetFlashModeButtonPressed(FlashMode.auto)
                      : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_on),
              color:
                  controller?.value.flashMode == FlashMode.always
                      ? Colors.orange
                      : Colors.blue,
              onPressed:
                  controller != null
                      ? () => onSetFlashModeButtonPressed(FlashMode.always)
                      : null,
            ),
            IconButton(
              icon: const Icon(Icons.highlight),
              color:
                  controller?.value.flashMode == FlashMode.torch
                      ? Colors.orange
                      : Colors.blue,
              onPressed:
                  controller != null
                      ? () => onSetFlashModeButtonPressed(FlashMode.torch)
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _exposureModeControlRowWidget() {
    final ButtonStyle styleAuto = TextButton.styleFrom(
      foregroundColor:
          controller?.value.exposureMode == ExposureMode.auto
              ? Colors.orange
              : Colors.blue,
    );
    final ButtonStyle styleLocked = TextButton.styleFrom(
      foregroundColor:
          controller?.value.exposureMode == ExposureMode.locked
              ? Colors.orange
              : Colors.blue,
    );

    return SizeTransition(
      sizeFactor: _exposureModeControlRowAnimation,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.grey.shade50,
          child: Column(
            children: <Widget>[
              const Center(child: Text('Exposure Mode')),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    style: styleAuto,
                    onPressed:
                        controller != null
                            ? () => onSetExposureModeButtonPressed(
                              ExposureMode.auto,
                            )
                            : null,
                    onLongPress: () {
                      if (controller != null) {
                        controller!.setExposurePoint(null);
                        showInSnackBar('Resetting exposure point');
                      }
                    },
                    child: const Text('AUTO'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed:
                        controller != null
                            ? () => onSetExposureModeButtonPressed(
                              ExposureMode.locked,
                            )
                            : null,
                    child: const Text('LOCKED'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed:
                        controller != null
                            ? () => controller!.setExposureOffset(0.0)
                            : null,
                    child: const Text('RESET OFFSET'),
                  ),
                ],
              ),
              const Center(child: Text('Exposure Offset')),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Text(_minAvailableExposureOffset.toString()),
                  Slider(
                    value: _currentExposureOffset,
                    min: _minAvailableExposureOffset,
                    max: _maxAvailableExposureOffset,
                    label: _currentExposureOffset.toString(),
                    onChanged:
                        _minAvailableExposureOffset ==
                                _maxAvailableExposureOffset
                            ? null
                            : setExposureOffset,
                  ),
                  Text(_maxAvailableExposureOffset.toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _focusModeControlRowWidget() {
    final ButtonStyle styleAuto = TextButton.styleFrom(
      foregroundColor:
          controller?.value.focusMode == FocusMode.auto
              ? Colors.orange
              : Colors.blue,
    );
    final ButtonStyle styleLocked = TextButton.styleFrom(
      foregroundColor:
          controller?.value.focusMode == FocusMode.locked
              ? Colors.orange
              : Colors.blue,
    );

    return SizeTransition(
      sizeFactor: _focusModeControlRowAnimation,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.grey.shade50,
          child: Column(
            children: <Widget>[
              const Center(child: Text('Focus Mode')),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    style: styleAuto,
                    onPressed:
                        controller != null
                            ? () => onSetFocusModeButtonPressed(FocusMode.auto)
                            : null,
                    onLongPress: () {
                      if (controller != null) {
                        controller!.setFocusPoint(null);
                      }
                      showInSnackBar('Resetting focus point');
                    },
                    child: const Text('AUTO'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed:
                        controller != null
                            ? () =>
                                onSetFocusModeButtonPressed(FocusMode.locked)
                            : null,
                    child: const Text('LOCKED'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    final CameraController? cameraController = controller;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          onPressed:
              cameraController != null &&
                      cameraController.value.isInitialized &&
                      !cameraController.value.isRecordingVideo
                  ? onTakePictureButtonPressed
                  : null,
        ),
        IconButton(
          icon: const Icon(Icons.videocam),
          color: Colors.blue,
          onPressed:
              cameraController != null &&
                      cameraController.value.isInitialized &&
                      !cameraController.value.isRecordingVideo
                  ? onVideoRecordButtonPressed
                  : null,
        ),
        IconButton(
          icon:
              cameraController != null &&
                      cameraController.value.isRecordingPaused
                  ? const Icon(Icons.play_arrow)
                  : const Icon(Icons.pause),
          color: Colors.blue,
          onPressed:
              cameraController != null &&
                      cameraController.value.isInitialized &&
                      cameraController.value.isRecordingVideo
                  ? cameraController.value.isRecordingPaused
                      ? onResumeButtonPressed
                      : onPauseButtonPressed
                  : null,
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          color: Colors.red,
          onPressed:
              cameraController != null &&
                      cameraController.value.isInitialized &&
                      cameraController.value.isRecordingVideo
                  ? onStopButtonPressed
                  : null,
        ),
        IconButton(
          icon: const Icon(Icons.pause_presentation),
          color:
              cameraController != null && cameraController.value.isPreviewPaused
                  ? Colors.red
                  : Colors.blue,
          onPressed:
              cameraController == null ? null : onPausePreviewButtonPressed,
        ),
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    void onChanged(CameraDescription? description) {
      if (description == null) {
        return;
      }

      onNewCameraSelected(description);
    }

    if (_cameras.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        showInSnackBar('No camera found.');
      });
      return const Text('None');
    } else {
      for (final CameraDescription cameraDescription in _cameras) {
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: onChanged,
            ),
          ),
        );
      }
    }

    return Row(children: toggles);
  }

  ///---------------------------------------------------------------------------
  /// 현재 시간을 밀리초로 반환 (파일명 생성 등에 사용)
  ///---------------------------------------------------------------------------
  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  ///---------------------------------------------------------------------------
  /// 스낵바로 메시지 표시 (상태 알림, 오류 등)
  ///---------------------------------------------------------------------------
  void showInSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  ///---------------------------------------------------------------------------
  /// 카메라 미리보기 탭 처리 - 탭한 위치에 노출/초점 설정
  ///---------------------------------------------------------------------------
  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    // 탭 위치를 0~1 사이의 상대 좌표로 변환
    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    // 해당 위치에 노출 및 초점 설정
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  ///---------------------------------------------------------------------------
  /// 새 카메라 선택 처리 (전면/후면 전환 등)
  ///---------------------------------------------------------------------------
  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      // 이미 초기화된 컨트롤러가 있으면 카메라만 변경
      return controller!.setDescription(cameraDescription);
    } else {
      // 아니면 새로 컨트롤러 초기화
      return _initializeCameraController(cameraDescription);
    }
  }

  ///---------------------------------------------------------------------------
  /// 카메라 컨트롤러 초기화 - 해상도, 오디오, 노출, 줌 등 설정
  ///---------------------------------------------------------------------------
  Future<void> _initializeCameraController(
    CameraDescription cameraDescription,
  ) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.medium, // 웹/앱에 따라 해상도 설정
      enableAudio: enableAudio, // 오디오 활성화 여부
      imageFormatGroup: ImageFormatGroup.jpeg, // 이미지 포맷
    );

    controller = cameraController;

    // 컨트롤러 상태 변화 감지 리스너
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar(
          'Camera error ${cameraController.value.errorDescription}',
        );
      }
    });

    try {
      // 카메라 초기화 및 설정값 가져오기
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        // 웹에서는 노출 모드 지원 안함
        ...!kIsWeb
            ? <Future<Object?>>[
              cameraController.getMinExposureOffset().then(
                (double value) => _minAvailableExposureOffset = value,
              ),
              cameraController.getMaxExposureOffset().then(
                (double value) => _maxAvailableExposureOffset = value,
              ),
            ]
            : <Future<Object?>>[],
        cameraController.getMaxZoomLevel().then(
          (double value) => _maxAvailableZoom = value,
        ),
        cameraController.getMinZoomLevel().then(
          (double value) => _minAvailableZoom = value,
        ),
      ]);
    } on CameraException catch (e) {
      // 카메라 권한 관련 예외 처리
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
        default:
          _showCameraException(e);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  ///---------------------------------------------------------------------------
  /// 사진 촬영 버튼 처리
  ///---------------------------------------------------------------------------
  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        setState(() {
          imageFile = file; // 촬영된 이미지 저장
          videoController?.dispose(); // 비디오 컨트롤러 정리
          videoController = null;
        });
        if (file != null) {
          showInSnackBar('Picture saved to ${file.path}');
        }
      }
    });
  }

  ///---------------------------------------------------------------------------
  /// 플래시 모드 버튼 처리 - 모드 선택 UI 표시/숨김
  ///---------------------------------------------------------------------------
  void onFlashModeButtonPressed() {
    if (_flashModeControlRowAnimationController.value == 1) {
      _flashModeControlRowAnimationController.reverse(); // 표시된 상태면 숨김
    } else {
      _flashModeControlRowAnimationController.forward(); // 숨겨진 상태면 표시
      _exposureModeControlRowAnimationController.reverse(); // 다른 모드 UI는 숨김
      _focusModeControlRowAnimationController.reverse();
    }
  }

  ///---------------------------------------------------------------------------
  /// 노출 모드 버튼 처리 - 모드 선택 UI 표시/숨김
  ///---------------------------------------------------------------------------
  void onExposureModeButtonPressed() {
    if (_exposureModeControlRowAnimationController.value == 1) {
      _exposureModeControlRowAnimationController.reverse(); // 표시된 상태면 숨김
    } else {
      _exposureModeControlRowAnimationController.forward(); // 숨겨진 상태면 표시
      _flashModeControlRowAnimationController.reverse(); // 다른 모드 UI는 숨김
      _focusModeControlRowAnimationController.reverse();
    }
  }

  ///---------------------------------------------------------------------------
  /// 포커스 모드 버튼 처리 - 모드 선택 UI 표시/숨김
  ///---------------------------------------------------------------------------
  void onFocusModeButtonPressed() {
    if (_focusModeControlRowAnimationController.value == 1) {
      _focusModeControlRowAnimationController.reverse(); // 표시된 상태면 숨김
    } else {
      _focusModeControlRowAnimationController.forward(); // 숨겨진 상태면 표시
      _flashModeControlRowAnimationController.reverse(); // 다른 모드 UI는 숨김
      _exposureModeControlRowAnimationController.reverse();
    }
  }

  ///---------------------------------------------------------------------------
  /// 오디오 모드 전환 버튼 처리
  ///---------------------------------------------------------------------------
  void onAudioModeButtonPressed() {
    enableAudio = !enableAudio; // 오디오 활성화 상태 토글
    if (controller != null) {
      onNewCameraSelected(controller!.description); // 카메라 재초기화
    }
  }

  ///---------------------------------------------------------------------------
  /// 캡처 방향 잠금 버튼 처리
  ///---------------------------------------------------------------------------
  Future<void> onCaptureOrientationLockButtonPressed() async {
    try {
      if (controller != null) {
        final CameraController cameraController = controller!;
        if (cameraController.value.isCaptureOrientationLocked) {
          // 잠금 해제
          await cameraController.unlockCaptureOrientation();
          showInSnackBar('Capture orientation unlocked');
        } else {
          // 현재 방향으로 잠금
          await cameraController.lockCaptureOrientation();
          showInSnackBar(
            'Capture orientation locked to ${cameraController.value.lockedCaptureOrientation.toString().split('.').last}',
          );
        }
      }
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  ///---------------------------------------------------------------------------
  /// 플래시 모드 설정 버튼 처리
  ///---------------------------------------------------------------------------
  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      // 설정된 모드 표시
      showInSnackBar('Flash mode set to ${mode.toString().split('.').last}');
    });
  }

  ///---------------------------------------------------------------------------
  /// 노출 모드 설정 버튼 처리
  ///---------------------------------------------------------------------------
  void onSetExposureModeButtonPressed(ExposureMode mode) {
    setExposureMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      // 설정된 모드 표시
      showInSnackBar('Exposure mode set to ${mode.toString().split('.').last}');
    });
  }

  ///---------------------------------------------------------------------------
  /// 포커스 모드 설정 버튼 처리
  ///---------------------------------------------------------------------------
  void onSetFocusModeButtonPressed(FocusMode mode) {
    setFocusMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      // 설정된 모드 표시
      showInSnackBar('Focus mode set to ${mode.toString().split('.').last}');
    });
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 시작 버튼 처리
  ///---------------------------------------------------------------------------
  void onVideoRecordButtonPressed() {
    startVideoRecording().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 정지 버튼 처리
  ///---------------------------------------------------------------------------
  void onStopButtonPressed() {
    stopVideoRecording().then((XFile? file) {
      if (mounted) {
        setState(() {});
      }
      if (file != null) {
        // 녹화 완료 메시지 표시
        showInSnackBar('Video recorded to ${file.path}');
        videoFile = file;
        // 녹화된 비디오 재생 시작
        _startVideoPlayer();
      }
    });
  }

  ///---------------------------------------------------------------------------
  /// 카메라 미리보기 일시정지/재개 버튼 처리
  ///---------------------------------------------------------------------------
  Future<void> onPausePreviewButtonPressed() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    // 미리보기 상태 토글
    if (cameraController.value.isPreviewPaused) {
      await cameraController.resumePreview(); // 재개
    } else {
      await cameraController.pausePreview(); // 일시정지
    }

    if (mounted) {
      setState(() {});
    }
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 일시정지 버튼 처리
  ///---------------------------------------------------------------------------
  void onPauseButtonPressed() {
    pauseVideoRecording().then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Video recording paused');
    });
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 재개 버튼 처리
  ///---------------------------------------------------------------------------
  void onResumeButtonPressed() {
    resumeVideoRecording().then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Video recording resumed');
    });
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 시작 기능
  ///---------------------------------------------------------------------------
  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // 이미 녹화중이면 아무 작업 안함
      return;
    }

    try {
      // 비디오 녹화 시작
      await cameraController.startVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 정지 기능 - 녹화된 파일 반환
  ///---------------------------------------------------------------------------
  Future<XFile?> stopVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      // 비디오 녹화 정지 및 파일 반환
      return cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 일시정지 기능
  ///---------------------------------------------------------------------------
  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      // 비디오 녹화 일시정지
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  ///---------------------------------------------------------------------------
  /// 비디오 녹화 재개 기능
  ///---------------------------------------------------------------------------
  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      // 비디오 녹화 재개
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setExposureMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setExposureOffset(double offset) async {
    if (controller == null) {
      return;
    }

    setState(() {
      _currentExposureOffset = offset;
    });
    try {
      offset = await controller!.setExposureOffset(offset);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setFocusMode(FocusMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFocusMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> _startVideoPlayer() async {
    if (videoFile == null) {
      return;
    }

    final VideoPlayerController vController =
        kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(videoFile!.path))
            : VideoPlayerController.file(File(videoFile!.path));

    videoPlayerListener = () {
      if (videoController != null) {
        // Refreshing the state to update video player with the correct ratio.
        if (mounted) {
          setState(() {});
        }
        videoController!.removeListener(videoPlayerListener!);
      }
    };
    vController.addListener(videoPlayerListener!);
    await vController.setLooping(true);
    await vController.initialize();
    await videoController?.dispose();
    if (mounted) {
      setState(() {
        imageFile = null;
        videoController = vController;
      });
    }
    await vController.play();
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

/// CameraApp is the Main Application.
class CameraApp extends StatelessWidget {
  /// Default Constructor
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CameraExampleHome());
  }
}

List<CameraDescription> _cameras = <CameraDescription>[];

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    _logError(e.code, e.description);
  }
  runApp(const CameraApp());
}
