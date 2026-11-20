import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @backToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Back to library'**
  String get backToLibrary;

  /// No description provided for @practiceMetronome.
  ///
  /// In en, this message translates to:
  /// **'Practice · Metronome'**
  String get practiceMetronome;

  /// No description provided for @noFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get noFolder;

  /// No description provided for @noTracksWithoutFolder.
  ///
  /// In en, this message translates to:
  /// **'No tracks without a folder'**
  String get noTracksWithoutFolder;

  /// No description provided for @addMp3Ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Add MP3 …'**
  String get addMp3Ellipsis;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolder;

  /// No description provided for @renameEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Rename …'**
  String get renameEllipsis;

  /// No description provided for @deleteNamedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deleteNamedTitle(String name);

  /// No description provided for @deleteFolderText.
  ///
  /// In en, this message translates to:
  /// **'The tracks stay in the library and appear under “No folder”.'**
  String get deleteFolderText;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty – drag tracks here'**
  String get emptyFolder;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @newFolderEllipsis.
  ///
  /// In en, this message translates to:
  /// **'New folder …'**
  String get newFolderEllipsis;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteTrackText.
  ///
  /// In en, this message translates to:
  /// **'The track is removed from the app. The original file stays unchanged.'**
  String get deleteTrackText;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameHint;

  /// No description provided for @editTrackEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Edit title and artist …'**
  String get editTrackEllipsis;

  /// No description provided for @editTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit track'**
  String get editTrackTitle;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @artistLabel.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artistLabel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @addMp3Shortcut.
  ///
  /// In en, this message translates to:
  /// **'Add MP3 ({shortcut})'**
  String addMp3Shortcut(String shortcut);

  /// No description provided for @newFolderShortcut.
  ///
  /// In en, this message translates to:
  /// **'New folder ({shortcut})'**
  String newFolderShortcut(String shortcut);

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @sortAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get sortAlphabetical;

  /// No description provided for @sortDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date added'**
  String get sortDateAdded;

  /// No description provided for @sortCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom order'**
  String get sortCustom;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @noTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks'**
  String get noTracks;

  /// No description provided for @emptyLibraryHintDrop.
  ///
  /// In en, this message translates to:
  /// **'Add MP3, WAV or FLAC files with + or drag them here.'**
  String get emptyLibraryHintDrop;

  /// No description provided for @emptyLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Add MP3, WAV or FLAC files with +.'**
  String get emptyLibraryHint;

  /// No description provided for @emptyLibraryHintBrowser.
  ///
  /// In en, this message translates to:
  /// **'Add MP3, WAV or FLAC files with + from the browser\'s file picker.'**
  String get emptyLibraryHintBrowser;

  /// No description provided for @addMp3.
  ///
  /// In en, this message translates to:
  /// **'Add MP3'**
  String get addMp3;

  /// No description provided for @folderActions.
  ///
  /// In en, this message translates to:
  /// **'Folder actions'**
  String get folderActions;

  /// No description provided for @trackActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get trackActions;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'{size} used'**
  String storageUsed(String size);

  /// No description provided for @storageFree.
  ///
  /// In en, this message translates to:
  /// **'{size} free'**
  String storageFree(String size);

  /// No description provided for @storagePersisted.
  ///
  /// In en, this message translates to:
  /// **'stored permanently'**
  String get storagePersisted;

  /// No description provided for @storageNotPersisted.
  ///
  /// In en, this message translates to:
  /// **'not stored permanently'**
  String get storageNotPersisted;

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get recording;

  /// No description provided for @recordingFileName.
  ///
  /// In en, this message translates to:
  /// **'Recording {stamp}'**
  String recordingFileName(String stamp);

  /// No description provided for @recordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording not possible: {detail}'**
  String recordingFailed(String detail);

  /// No description provided for @recordingErrorInvalidPath.
  ///
  /// In en, this message translates to:
  /// **'No file path for the recording.'**
  String get recordingErrorInvalidPath;

  /// No description provided for @recordingErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Recording requires macOS 14.2 or later.'**
  String get recordingErrorUnsupported;

  /// No description provided for @recordingErrorTap.
  ///
  /// In en, this message translates to:
  /// **'The system audio could not be tapped.'**
  String get recordingErrorTap;

  /// No description provided for @recordingErrorTapFormat.
  ///
  /// In en, this message translates to:
  /// **'The system audio has an unexpected format.'**
  String get recordingErrorTapFormat;

  /// No description provided for @recordingErrorNoOutput.
  ///
  /// In en, this message translates to:
  /// **'No output device found.'**
  String get recordingErrorNoOutput;

  /// No description provided for @recordingErrorAggregate.
  ///
  /// In en, this message translates to:
  /// **'The recording device could not be set up.'**
  String get recordingErrorAggregate;

  /// No description provided for @recordingErrorOutOfMemory.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory for the recording.'**
  String get recordingErrorOutOfMemory;

  /// No description provided for @recordingErrorFile.
  ///
  /// In en, this message translates to:
  /// **'The recording file could not be created.'**
  String get recordingErrorFile;

  /// No description provided for @recordingErrorIoProc.
  ///
  /// In en, this message translates to:
  /// **'The audio stream for the recording could not be set up.'**
  String get recordingErrorIoProc;

  /// No description provided for @recordingErrorStart.
  ///
  /// In en, this message translates to:
  /// **'The recording could not be started.'**
  String get recordingErrorStart;

  /// No description provided for @recordingErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error ({code}).'**
  String recordingErrorUnknown(int code);

  /// No description provided for @recordingSilent.
  ///
  /// In en, this message translates to:
  /// **'Only silence is coming in. Is music playing? Otherwise grant the permission: System Settings › Privacy & Security › Screen & System Audio Recording.'**
  String get recordingSilent;

  /// No description provided for @recordingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Records the system audio (without microphone). The recording is only stored locally and then added to the library.'**
  String get recordingTooltip;

  /// No description provided for @noTrackSelected.
  ///
  /// In en, this message translates to:
  /// **'No track selected'**
  String get noTrackSelected;

  /// No description provided for @openFileHintDrop.
  ///
  /// In en, this message translates to:
  /// **'Open an MP3, WAV or FLAC file or drag it into the window.'**
  String get openFileHintDrop;

  /// No description provided for @openFileHintFiles.
  ///
  /// In en, this message translates to:
  /// **'Open an MP3, WAV or FLAC file from “Files”.'**
  String get openFileHintFiles;

  /// No description provided for @openFileHintBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open an MP3, WAV or FLAC file with the browser\'s file picker.'**
  String get openFileHintBrowser;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get openFile;

  /// No description provided for @loopLength.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String loopLength(double seconds);

  /// No description provided for @loopPass.
  ///
  /// In en, this message translates to:
  /// **'pass {current} of {total}'**
  String loopPass(String current, String total);

  /// No description provided for @loopOn.
  ///
  /// In en, this message translates to:
  /// **'Loop on'**
  String get loopOn;

  /// No description provided for @loopOff.
  ///
  /// In en, this message translates to:
  /// **'Loop off'**
  String get loopOff;

  /// No description provided for @loopLabel.
  ///
  /// In en, this message translates to:
  /// **'LOOP'**
  String get loopLabel;

  /// No description provided for @setStartHere.
  ///
  /// In en, this message translates to:
  /// **'S here'**
  String get setStartHere;

  /// No description provided for @setStartHereTooltip.
  ///
  /// In en, this message translates to:
  /// **'Use the current playback position as start'**
  String get setStartHereTooltip;

  /// No description provided for @setEndHere.
  ///
  /// In en, this message translates to:
  /// **'E here'**
  String get setEndHere;

  /// No description provided for @setEndHereTooltip.
  ///
  /// In en, this message translates to:
  /// **'Use the current playback position as end'**
  String get setEndHereTooltip;

  /// No description provided for @toLoopStart.
  ///
  /// In en, this message translates to:
  /// **'To loop start'**
  String get toLoopStart;

  /// No description provided for @jumpToLoopStart.
  ///
  /// In en, this message translates to:
  /// **'Jump to loop start'**
  String get jumpToLoopStart;

  /// No description provided for @wholeTrack.
  ///
  /// In en, this message translates to:
  /// **'Whole track'**
  String get wholeTrack;

  /// No description provided for @loopTooShort.
  ///
  /// In en, this message translates to:
  /// **'The end must be at least 1 second after the start.'**
  String get loopTooShort;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @speedTooltip.
  ///
  /// In en, this message translates to:
  /// **'The pitch stays the same.'**
  String get speedTooltip;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'{rate}×'**
  String rate(double rate);

  /// No description provided for @percent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String percent(int value);

  /// No description provided for @rampTitle.
  ///
  /// In en, this message translates to:
  /// **'Ramp-up'**
  String get rampTitle;

  /// No description provided for @rampSettingsOpen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get rampSettingsOpen;

  /// No description provided for @rampSettingsClose.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get rampSettingsClose;

  /// No description provided for @rampSummary.
  ///
  /// In en, this message translates to:
  /// **'+{step}% after {passes, plural, =1{1 pass} other{{passes} passes}}'**
  String rampSummary(int step, int passes);

  /// No description provided for @rampStartLevel.
  ///
  /// In en, this message translates to:
  /// **'Start level'**
  String get rampStartLevel;

  /// No description provided for @rampTargetLevel.
  ///
  /// In en, this message translates to:
  /// **'Target level'**
  String get rampTargetLevel;

  /// No description provided for @rampStepSize.
  ///
  /// In en, this message translates to:
  /// **'Step size'**
  String get rampStepSize;

  /// No description provided for @rampStepOption.
  ///
  /// In en, this message translates to:
  /// **'+{step}%'**
  String rampStepOption(int step);

  /// No description provided for @rampPassesPerLevel.
  ///
  /// In en, this message translates to:
  /// **'Passes per level'**
  String get rampPassesPerLevel;

  /// No description provided for @rampNotCountingHint.
  ///
  /// In en, this message translates to:
  /// **'Passes only count with speed on and an active loop.'**
  String get rampNotCountingHint;

  /// No description provided for @rampHint.
  ///
  /// In en, this message translates to:
  /// **'A pass counts at the jump from the loop end to the start. Changing loop or speed by hand resets the counter.'**
  String get rampHint;

  /// No description provided for @rampStatus.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · {passes} of {total}'**
  String rampStatus(int percent, int passes, int total);

  /// No description provided for @rampStatusTarget.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · target reached · {passes, plural, =1{1 pass} other{{passes} passes}}'**
  String rampStatusTarget(int percent, int passes);

  /// No description provided for @back15.
  ///
  /// In en, this message translates to:
  /// **'15 seconds back'**
  String get back15;

  /// No description provided for @forward15.
  ///
  /// In en, this message translates to:
  /// **'15 seconds forward'**
  String get forward15;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @spaceKey.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get spaceKey;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @metronome.
  ///
  /// In en, this message translates to:
  /// **'Metronome'**
  String get metronome;

  /// No description provided for @subdivisionQuarter.
  ///
  /// In en, this message translates to:
  /// **'Quarters'**
  String get subdivisionQuarter;

  /// No description provided for @subdivisionEighth.
  ///
  /// In en, this message translates to:
  /// **'Eighths'**
  String get subdivisionEighth;

  /// No description provided for @subdivisionTriplet.
  ///
  /// In en, this message translates to:
  /// **'Triplets'**
  String get subdivisionTriplet;

  /// No description provided for @subdivisionSixteenth.
  ///
  /// In en, this message translates to:
  /// **'Sixteenths'**
  String get subdivisionSixteenth;

  /// No description provided for @metronomeStartKey.
  ///
  /// In en, this message translates to:
  /// **'Start (M)'**
  String get metronomeStartKey;

  /// No description provided for @metronomeStopKey.
  ///
  /// In en, this message translates to:
  /// **'Stop (M)'**
  String get metronomeStopKey;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @slower.
  ///
  /// In en, this message translates to:
  /// **'Slower (↓)'**
  String get slower;

  /// No description provided for @faster.
  ///
  /// In en, this message translates to:
  /// **'Faster (↑)'**
  String get faster;

  /// No description provided for @bpm.
  ///
  /// In en, this message translates to:
  /// **'{bpm} BPM'**
  String bpm(int bpm);

  /// No description provided for @tap.
  ///
  /// In en, this message translates to:
  /// **'Tap'**
  String get tap;

  /// No description provided for @tapKey.
  ///
  /// In en, this message translates to:
  /// **'Tap (T)'**
  String get tapKey;

  /// No description provided for @metronomeKeysHint.
  ///
  /// In en, this message translates to:
  /// **'Keys: M = start/stop, ↑ / ↓ = tempo ±1 (with Shift ±10), T = tap tempo. Track and metronome never play at the same time.'**
  String get metronomeKeysHint;

  /// No description provided for @meterAndSound.
  ///
  /// In en, this message translates to:
  /// **'Meter and sound'**
  String get meterAndSound;

  /// No description provided for @autoTempoRamp.
  ///
  /// In en, this message translates to:
  /// **'Automatic tempo increase'**
  String get autoTempoRamp;

  /// No description provided for @rampByTimeHint.
  ///
  /// In en, this message translates to:
  /// **'The tempo changes evenly in 1 BPM steps over the duration, each time at the start of a bar. Once the target is reached, it stays for one step and then starts again at the start BPM.'**
  String get rampByTimeHint;

  /// No description provided for @rampByBarsHint.
  ///
  /// In en, this message translates to:
  /// **'The tempo rises at the start of a bar. Once the target is reached, it stays for as many bars and then starts again at the start BPM.'**
  String get rampByBarsHint;

  /// No description provided for @bars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get bars;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @startBpm.
  ///
  /// In en, this message translates to:
  /// **'Start BPM'**
  String get startBpm;

  /// No description provided for @targetBpm.
  ///
  /// In en, this message translates to:
  /// **'Target BPM'**
  String get targetBpm;

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes)'**
  String get durationMinutes;

  /// No description provided for @step.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get step;

  /// No description provided for @bpmStep.
  ///
  /// In en, this message translates to:
  /// **'+{step} BPM'**
  String bpmStep(int step);

  /// No description provided for @everyBars.
  ///
  /// In en, this message translates to:
  /// **'Every … bars'**
  String get everyBars;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @moduleRampTime.
  ///
  /// In en, this message translates to:
  /// **'Auto {start}→{target} BPM in {minutes} min'**
  String moduleRampTime(int start, int target, int minutes);

  /// No description provided for @moduleRampBars.
  ///
  /// In en, this message translates to:
  /// **'Auto +{step} BPM / {bars, plural, =1{1 bar} other{{bars} bars}}'**
  String moduleRampBars(int step, int bars);

  /// No description provided for @moduleDetails.
  ///
  /// In en, this message translates to:
  /// **'BPM · {meter} · {subdivision}'**
  String moduleDetails(String meter, String subdivision);

  /// No description provided for @loadNotFound.
  ///
  /// In en, this message translates to:
  /// **'The file “{file}” was not found. Was it moved or deleted?'**
  String loadNotFound(String file);

  /// No description provided for @loadUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The file “{file}” is not a supported audio format (MP3, WAV, FLAC) or is damaged.'**
  String loadUnsupported(String file);

  /// No description provided for @loadUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The file “{file}” cannot be read. Are access rights missing?'**
  String loadUnreadable(String file);

  /// No description provided for @loadNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No audio device available. Please check headphones or speakers and try again.'**
  String get loadNoDevice;

  /// No description provided for @loadOutOfMemory.
  ///
  /// In en, this message translates to:
  /// **'The file “{file}” is too large for the free memory.'**
  String loadOutOfMemory(String file);

  /// No description provided for @loadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Loading was cancelled.'**
  String get loadCancelled;

  /// No description provided for @loadBusy.
  ///
  /// In en, this message translates to:
  /// **'The audio core is busy right now. Please try again.'**
  String get loadBusy;

  /// No description provided for @loadUnsupportedSampleRate.
  ///
  /// In en, this message translates to:
  /// **'The audio output runs at too low a sample rate. At least 8 kHz is needed.'**
  String get loadUnsupportedSampleRate;

  /// No description provided for @loadInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid file reference.'**
  String get loadInvalid;

  /// No description provided for @loadUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error while loading (code {code}).'**
  String loadUnknown(int code);

  /// No description provided for @libraryCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The library was damaged and was kept as “{backup}”.'**
  String libraryCorrupt(String backup);

  /// No description provided for @libraryTooNew.
  ///
  /// In en, this message translates to:
  /// **'This library was saved by a newer version of Woodshed Player. Please update the app. Until then, nothing is saved.'**
  String get libraryTooNew;

  /// No description provided for @librarySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The library could not be saved: {detail}'**
  String librarySaveFailed(String detail);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'The following files could not be imported:\n{files}'**
  String importFailed(String files);

  /// Track context menu switch (#37): the audio file stays on this device, its data are synced anyway.
  ///
  /// In en, this message translates to:
  /// **'Don\'t upload'**
  String get dontUpload;

  /// Folder context menu switch (#37): upload the audio files of this folder to the cloud.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncFolder;

  /// Track row (#37): the audio file is on another device and not in the cloud.
  ///
  /// In en, this message translates to:
  /// **'File only on one device'**
  String get fileOnOneDevice;

  /// Sync (#10/AK7): state.json in the cloud is damaged; nothing was merged, local data unchanged.
  ///
  /// In en, this message translates to:
  /// **'The library in the cloud is damaged and was not applied. Your data on this device are unchanged; syncing waits until the cloud holds a readable library again.'**
  String get cloudStateUnreadable;

  /// Sync (#10/AK7): state.json in the cloud has a newer format version.
  ///
  /// In en, this message translates to:
  /// **'The library in the cloud was saved by a newer version of Woodshed Player. Please update the app. Until then, nothing is synced.'**
  String get cloudStateTooNew;

  /// No description provided for @trackNotOnDevice.
  ///
  /// In en, this message translates to:
  /// **'The audio file of «{title}» is only on another device and not in the cloud.'**
  String trackNotOnDevice(String title);

  /// Library header button and macOS app menu item (#50): opens the About dialog.
  ///
  /// In en, this message translates to:
  /// **'About Woodshed Player'**
  String get aboutApp;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Open source under the MIT License. The name “Woodshed Player” is not covered by it.'**
  String get aboutLicense;

  /// About dialog link (#50): opens the published privacy policy in the browser.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get termsOfUse;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// About dialog (#50): latest Git tag of this build.
  ///
  /// In en, this message translates to:
  /// **'Tag {tag}'**
  String aboutTag(String tag);

  /// About dialog (#50): the build has no Git tag.
  ///
  /// In en, this message translates to:
  /// **'No tag'**
  String get aboutNoTag;

  /// No description provided for @aboutBuildDate.
  ///
  /// In en, this message translates to:
  /// **'Built on {date}'**
  String aboutBuildDate(DateTime date);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
