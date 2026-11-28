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

  /// #146/AK1: title of the name dialog for a folder inside a folder
  ///
  /// In en, this message translates to:
  /// **'New subfolder'**
  String get newSubfolder;

  /// #146/AK1: context menu of a folder
  ///
  /// In en, this message translates to:
  /// **'New subfolder …'**
  String get newSubfolderEllipsis;

  /// #146/AK5: question before deleting a folder with subfolders: folders deleted (with this one), tracks moved to “No folder”
  ///
  /// In en, this message translates to:
  /// **'{folders, plural, =1{1 folder is deleted.} other{{folders} folders are deleted: this one and its subfolders.}} {tracks, plural, =0{There are no tracks in them.} =1{1 track moves to “No folder”, its audio file stays.} other{{tracks} tracks move to “No folder”, their audio files stay.}}'**
  String deleteFolderTreeText(int folders, int tracks);

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

  /// No description provided for @libraryMore.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get libraryMore;

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

  /// No description provided for @recordingErrorNoInput.
  ///
  /// In en, this message translates to:
  /// **'No microphone found, or it could not be opened.'**
  String get recordingErrorNoInput;

  /// No description provided for @recordingErrorInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'The threshold or the pause of the armed recording is out of range.'**
  String get recordingErrorInvalidArgument;

  /// No description provided for @recordingArmed.
  ///
  /// In en, this message translates to:
  /// **'Armed'**
  String get recordingArmed;

  /// No description provided for @recordingArmedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Armed from the command line: the recording starts with the first sound and ends after a pause. Click to cancel; once it records, a click stops it.'**
  String get recordingArmedTooltip;

  /// No description provided for @recordingSource.
  ///
  /// In en, this message translates to:
  /// **'Recording source'**
  String get recordingSource;

  /// No description provided for @recordingSourceSystem.
  ///
  /// In en, this message translates to:
  /// **'System audio'**
  String get recordingSourceSystem;

  /// No description provided for @recordingSourceMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get recordingSourceMicrophone;

  /// No description provided for @recordingTooltipMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Records through the microphone (the default input device). The recording is only stored locally and then added to the library.'**
  String get recordingTooltipMicrophone;

  /// No description provided for @recordingMicrophoneDenied.
  ///
  /// In en, this message translates to:
  /// **'Woodshed Player may not use the microphone. Grant access in System Settings › Privacy & Security › Microphone, then start the recording again.'**
  String get recordingMicrophoneDenied;

  /// No description provided for @recordingMicrophoneSilent.
  ///
  /// In en, this message translates to:
  /// **'Only silence is coming from the microphone. Check the input device in System Settings › Sound › Input.'**
  String get recordingMicrophoneSilent;

  /// No description provided for @recordingMicrophoneDeniedBrowser.
  ///
  /// In en, this message translates to:
  /// **'The browser does not let this website use the microphone. Allow the microphone for this website in the browser\'s site settings, then start the recording again.'**
  String get recordingMicrophoneDeniedBrowser;

  /// No description provided for @recordingMicrophoneSilentBrowser.
  ///
  /// In en, this message translates to:
  /// **'Only silence is coming from the microphone. Check which microphone the browser uses for this website and that it is not muted.'**
  String get recordingMicrophoneSilentBrowser;

  /// No description provided for @recordingStoppedInBackground.
  ///
  /// In en, this message translates to:
  /// **'The recording ended because the app went to the background or the screen was locked. What was recorded until then is in the library.'**
  String get recordingStoppedInBackground;

  /// No description provided for @recordingStorageFull.
  ///
  /// In en, this message translates to:
  /// **'The recording ended because the storage of this browser is full. What was recorded until then is in the library. Delete tracks or recordings to make room.'**
  String get recordingStorageFull;

  /// No description provided for @armedMicrophoneDeniedBrowser.
  ///
  /// In en, this message translates to:
  /// **'The browser does not let this website use the microphone, so «Armed» is off again. Allow the microphone for this website in the browser\'s site settings, then switch it on again.'**
  String get armedMicrophoneDeniedBrowser;

  /// No description provided for @armedStoppedInBackground.
  ///
  /// In en, this message translates to:
  /// **'«Armed» went off because the app went to the background or the screen was locked. A running recording was saved.'**
  String get armedStoppedInBackground;

  /// No description provided for @armedStorageFull.
  ///
  /// In en, this message translates to:
  /// **'«Armed» went off because the storage of this browser is full. A running recording was saved up to that point.'**
  String get armedStorageFull;

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

  /// No description provided for @openFileHintDialog.
  ///
  /// In en, this message translates to:
  /// **'Open an MP3, WAV or FLAC file.'**
  String get openFileHintDialog;

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

  /// #97: the core accepts sample rates from WP_MIN_SAMPLE_RATE to WP_MAX_SAMPLE_RATE, given in kHz.
  ///
  /// In en, this message translates to:
  /// **'The audio output runs at an unsupported sample rate. Supported are {min} to {max} kHz.'**
  String loadUnsupportedSampleRate(int min, int max);

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

  /// macOS menu bar (#144). The menu items follow the standard macOS titles of the language.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get menuServices;

  /// No description provided for @menuHide.
  ///
  /// In en, this message translates to:
  /// **'Hide Woodshed Player'**
  String get menuHide;

  /// No description provided for @menuHideOthers.
  ///
  /// In en, this message translates to:
  /// **'Hide Others'**
  String get menuHideOthers;

  /// No description provided for @menuShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show All'**
  String get menuShowAll;

  /// No description provided for @menuQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Woodshed Player'**
  String get menuQuit;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get menuUndo;

  /// No description provided for @menuRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get menuRedo;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @menuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuDelete;

  /// No description provided for @menuSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get menuSelectAll;

  /// No description provided for @menuSpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get menuSpeech;

  /// No description provided for @menuStartSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Start Speaking'**
  String get menuStartSpeaking;

  /// No description provided for @menuStopSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Stop Speaking'**
  String get menuStopSpeaking;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Enter Full Screen'**
  String get menuFullScreen;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @menuMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get menuMinimize;

  /// No description provided for @menuZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get menuZoom;

  /// No description provided for @menuBringAllToFront.
  ///
  /// In en, this message translates to:
  /// **'Bring All to Front'**
  String get menuBringAllToFront;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

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

  /// #39/AK4: track row, the audio file is not on this device but in the cloud; it loads when played
  ///
  /// In en, this message translates to:
  /// **'Only in the cloud'**
  String get onlyInCloud;

  /// #39/AK4: track row while its file is downloaded
  ///
  /// In en, this message translates to:
  /// **'Loading from the cloud …'**
  String get loadingFromCloud;

  /// #39/AK3: track menu, the file stays on this device whatever the cache limit
  ///
  /// In en, this message translates to:
  /// **'Keep offline'**
  String get keepOffline;

  /// #39/AK3: part of the storage line in the library footer
  ///
  /// In en, this message translates to:
  /// **'limit {size}'**
  String storageCacheLimit(String size);

  /// #39/AK3: dialog opened from the storage line
  ///
  /// In en, this message translates to:
  /// **'Offline storage for audio'**
  String get cacheLimitTitle;

  /// No description provided for @cacheLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Audio files on this device up to this limit. Above it, the tracks played longest ago are removed from this device; they stay in the library and in the cloud and load again when played. Tracks marked «Keep offline» always stay. The setting applies to this device only.'**
  String get cacheLimitHint;

  /// No description provided for @cacheLimitUsed.
  ///
  /// In en, this message translates to:
  /// **'{size} of audio on this device'**
  String cacheLimitUsed(String size);

  /// #39/AK6: banner on iPhone/iPad in the browser while the app is not installed
  ///
  /// In en, this message translates to:
  /// **'Install the app: tap Share, then «Add to Home Screen».'**
  String get installHint;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// #107: banner in the library while own tracks or folders are held back from the sync
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sync: keep 1 track or folder that was only on this device?} other{Sync: keep {count} tracks and folders that were only on this device?}}'**
  String heldHint(int count);

  /// #107: button of the banner that opens the question
  ///
  /// In en, this message translates to:
  /// **'Decide …'**
  String get heldDecide;

  /// No description provided for @heldTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep tracks and folders?'**
  String get heldTitle;

  /// #107: start of the question, followed by the first names
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This device was offline for a long time. This track or folder was never synced and may have been deleted on another device meanwhile:} other{This device was offline for a long time. These {count} tracks and folders were never synced and may have been deleted on another device meanwhile:}}'**
  String heldText(int count);

  /// #107: after the first 10 names
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more} other{and {count} more}}'**
  String heldMore(int count);

  /// No description provided for @heldExplain.
  ///
  /// In en, this message translates to:
  /// **'Keep: they stay here and go to your other devices. Remove: they are deleted on this device, with their audio files; the tracks of a removed folder or playlist stay.'**
  String get heldExplain;

  /// No description provided for @heldKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get heldKeep;

  /// No description provided for @heldRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get heldRemove;

  /// No description provided for @heldLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get heldLater;

  /// #114: section of the library
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// #114: title of the name dialog and default name
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// #114: menu item
  ///
  /// In en, this message translates to:
  /// **'New playlist …'**
  String get newPlaylistEllipsis;

  /// #114: title of the name dialog
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get renamePlaylist;

  /// #114
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// #114: question before deleting a playlist
  ///
  /// In en, this message translates to:
  /// **'The tracks stay in the library.'**
  String get deletePlaylistText;

  /// #114: plays the playlist from its first track
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playPlaylist;

  /// #114: tooltip of the «⋯» button
  ///
  /// In en, this message translates to:
  /// **'Playlist actions'**
  String get playlistActions;

  /// #124: submenu of a playlist; sorts it once, the result becomes its own order
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortPlaylistBy;

  /// #124: one entry of «Sort by»: the criterion and the direction
  ///
  /// In en, this message translates to:
  /// **'{key, select, title{Title} artist{Artist} duration{Duration} other{Date added}}, {direction, select, descending{descending} other{ascending}}'**
  String sortPlaylistOption(String key, String direction);

  /// #114: submenu of a track
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// #114: the track stays in the library
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// #114
  ///
  /// In en, this message translates to:
  /// **'Empty – drag tracks here'**
  String get emptyPlaylist;

  /// #114/AK9: synced with the paired devices
  ///
  /// In en, this message translates to:
  /// **'On all devices'**
  String get playlistOnAllDevices;

  /// #114/AK9: never leaves this device
  ///
  /// In en, this message translates to:
  /// **'Only on this device'**
  String get playlistOnThisDevice;

  /// #115: label of the tab bar for Player, Practice and Metronome
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get areas;

  /// #115: area with the library and simple playback
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get areaPlayer;

  /// #115: area with loop, tempo and ramp
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get areaPractice;

  /// #115: area with the metronome alone
  ///
  /// In en, this message translates to:
  /// **'Metronome'**
  String get areaMetronome;

  /// #115: tab of the area where something plays (screen readers)
  ///
  /// In en, this message translates to:
  /// **'{area}, running'**
  String areaRunning(String area);

  /// #115/AK8: plays the list in a random order
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// #115/AK8: state of the shuffle button
  ///
  /// In en, this message translates to:
  /// **'Shuffle on'**
  String get shuffleOn;

  /// #115/AK8
  ///
  /// In en, this message translates to:
  /// **'Repeat: off'**
  String get repeatOff;

  /// #115/AK8: the list starts over after its last track
  ///
  /// In en, this message translates to:
  /// **'Repeat: list'**
  String get repeatList;

  /// #115/AK8: the track starts over
  ///
  /// In en, this message translates to:
  /// **'Repeat: track'**
  String get repeatTrack;

  /// #115/AK9: to the start; within the first 3 s to the previous track
  ///
  /// In en, this message translates to:
  /// **'To start or previous track'**
  String get previousTrack;

  /// #115/AK9
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get nextTrack;

  /// #115: the folder or playlist the track plays from
  ///
  /// In en, this message translates to:
  /// **'From «{list}»'**
  String playingFrom(String list);

  /// #115: Practice: goes to the library in the area Player
  ///
  /// In en, this message translates to:
  /// **'Choose another track ›'**
  String get chooseOtherTrack;

  /// #115: mini bar of a paused track; time is mm:ss
  ///
  /// In en, this message translates to:
  /// **'paused · {time}'**
  String miniPaused(String time);

  /// #115/AK6: mini bar in the area Metronome
  ///
  /// In en, this message translates to:
  /// **'Play track, stops the metronome'**
  String get miniPlayTrack;

  /// #115: mini bar while the metronome runs
  ///
  /// In en, this message translates to:
  /// **'Metronome · {bpm} BPM'**
  String miniMetronome(int bpm);

  /// #115/AK11: search field of the library (⌘K)
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchLibrary;

  /// #115: search without a match
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noSearchResults;

  /// #116/AK1: context menu item of a track
  ///
  /// In en, this message translates to:
  /// **'Trim start and end …'**
  String get trimTrackEllipsis;

  /// #116, #120/AK1: hint of the greyed out menu item for file types that cannot be trimmed
  ///
  /// In en, this message translates to:
  /// **'This file type cannot be trimmed.'**
  String get trimUnavailable;

  /// #116/AK1: title of the trim view
  ///
  /// In en, this message translates to:
  /// **'Trim «{title}»'**
  String trimTitle(String title);

  /// #116/AK1: field and handle of the new start
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get trimStart;

  /// #116/AK1: field and handle of the new end
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get trimEnd;

  /// #116/AK1: length between the bounds, mm:ss.d
  ///
  /// In en, this message translates to:
  /// **'Remaining: {length}'**
  String trimRemaining(String length);

  /// #116/AK1: hint in the time fields
  ///
  /// In en, this message translates to:
  /// **'mm:ss.d'**
  String get trimTimeHint;

  /// #116/AK7: bounds that cannot be used
  ///
  /// In en, this message translates to:
  /// **'At least 1 s must remain, and the end must lie after the start.'**
  String get trimRangeInvalid;

  /// #116/AK2: plays the part between the bounds
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get trimPreview;

  /// #116/AK2: stops listening
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get trimStopPreview;

  /// #116/AK3: asks before trimming
  ///
  /// In en, this message translates to:
  /// **'Trim …'**
  String get trimApply;

  /// #116/AK3: title of the question before trimming
  ///
  /// In en, this message translates to:
  /// **'Trim the audio file?'**
  String get trimConfirmTitle;

  /// #116/AK3: question before trimming; start and end as mm:ss.d
  ///
  /// In en, this message translates to:
  /// **'The audio file of «{title}» keeps only {start} to {end}. The parts cut off are deleted; this cannot be undone.'**
  String trimConfirmText(String title, String start, String end);

  /// #116/AK3: confirms trimming
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get trimConfirm;

  /// #116: while the file is trimmed
  ///
  /// In en, this message translates to:
  /// **'Trimming …'**
  String get trimming;

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: this file type cannot be trimmed, or the file is damaged.'**
  String trimFailedFormat(String title);

  /// #120/AK5
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: the file has several audio tracks. The track is unchanged.'**
  String trimFailedMultipleTracks(String title);

  /// #120/AK5
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: the file is a fragmented MP4, which cannot be trimmed. The track is unchanged.'**
  String trimFailedFragmented(String title);

  /// #116/AK7, AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» was not trimmed: at least 1 s must remain.'**
  String trimFailedTooShort(String title);

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: its audio file is not on this device.'**
  String trimFailedNotOnDevice(String title);

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: there is not enough storage space. The track is unchanged.'**
  String trimFailedNoSpace(String title);

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: there is not enough memory. The track is unchanged.'**
  String trimFailedMemory(String title);

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: the library is from a newer version of the app and is read-only.'**
  String trimFailedReadOnly(String title);

  /// #116/AK9
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be trimmed: the file could not be read or written. The track is unchanged.'**
  String trimFailedOther(String title);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @syncSection.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncSection;

  /// No description provided for @syncOff.
  ///
  /// In en, this message translates to:
  /// **'Off – everything stays on this device'**
  String get syncOff;

  /// No description provided for @syncGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Drive'**
  String get syncGoogle;

  /// No description provided for @syncGoogleWebOnly.
  ///
  /// In en, this message translates to:
  /// **'On iPhone and iPad, sync with Google Drive runs in the web app.'**
  String get syncGoogleWebOnly;

  /// Settings, Sync: on Linux without libsecret (#161) Google Drive is not offered; says what to install.
  ///
  /// In en, this message translates to:
  /// **'Sync with Google Drive needs libsecret, which keeps the sign-in in the keyring of your system. Install it (on Debian and Ubuntu: libsecret-1-0) and start the app again.'**
  String get syncNoSecretStore;

  /// No description provided for @syncSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get syncSignIn;

  /// No description provided for @syncSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the sign-in in the browser …'**
  String get syncSigningIn;

  /// No description provided for @syncSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'The sign-in did not work. Try again.'**
  String get syncSignInFailed;

  /// No description provided for @syncSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'The sign-in at Google has expired. Sign in again to keep syncing.'**
  String get syncSignInAgain;

  /// No description provided for @syncBrowserDone.
  ///
  /// In en, this message translates to:
  /// **'Signed in. You can close this window and go back to Woodshed Player.'**
  String get syncBrowserDone;

  /// No description provided for @syncNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get syncNotSignedIn;

  /// No description provided for @syncSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get syncSignOut;

  /// No description provided for @syncSignOutText.
  ///
  /// In en, this message translates to:
  /// **'The sign-in is removed from this device and the sync stops. The library stays on this device, the files in Google Drive stay there too.'**
  String get syncSignOutText;

  /// No description provided for @syncStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get syncStatusOff;

  /// No description provided for @syncStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first sync'**
  String get syncStatusWaiting;

  /// No description provided for @syncStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get syncStatusIdle;

  /// No description provided for @syncStatusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing …'**
  String get syncStatusSyncing;

  /// No description provided for @syncStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection – changes wait and are sent later'**
  String get syncStatusOffline;

  /// No description provided for @syncStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Some files could not be synced'**
  String get syncStatusFailed;

  /// No description provided for @syncStatusTooNew.
  ///
  /// In en, this message translates to:
  /// **'Google Drive holds a newer format. Update the app.'**
  String get syncStatusTooNew;

  /// No description provided for @syncStatusForeign.
  ///
  /// In en, this message translates to:
  /// **'Google Drive holds another library.'**
  String get syncStatusForeign;

  /// No description provided for @syncLastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String syncLastSync(String time);

  /// No description provided for @syncNever.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNever;

  /// No description provided for @syncErrors.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file failed} other{{count} files failed}}'**
  String syncErrors(int count);

  /// No description provided for @syncDevices.
  ///
  /// In en, this message translates to:
  /// **'Last sync per device'**
  String get syncDevices;

  /// No description provided for @syncThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get syncThisDevice;

  /// No description provided for @syncDevice.
  ///
  /// In en, this message translates to:
  /// **'Device {id}'**
  String syncDevice(String id);

  /// No description provided for @syncUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get syncUnknown;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncRestoreEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Restore backup …'**
  String get syncRestoreEllipsis;

  /// No description provided for @syncRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get syncRestoreTitle;

  /// No description provided for @syncRestoreText.
  ///
  /// In en, this message translates to:
  /// **'The library goes back to the chosen state, on all devices. Changes made since then are undone.'**
  String get syncRestoreText;

  /// No description provided for @syncRestoreNone.
  ///
  /// In en, this message translates to:
  /// **'No backups yet.'**
  String get syncRestoreNone;

  /// No description provided for @syncBackupOf.
  ///
  /// In en, this message translates to:
  /// **'State of {time}'**
  String syncBackupOf(String time);

  /// No description provided for @syncRestoreDone.
  ///
  /// In en, this message translates to:
  /// **'Backup restored.'**
  String get syncRestoreDone;

  /// No description provided for @syncFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Folders to sync'**
  String get syncFoldersTitle;

  /// No description provided for @syncFoldersText.
  ///
  /// In en, this message translates to:
  /// **'Choose the folders whose audio files go to Google Drive. Titles, folders and settings are always synced.'**
  String get syncFoldersText;

  /// No description provided for @syncFree.
  ///
  /// In en, this message translates to:
  /// **'Free in Google Drive: {size}'**
  String syncFree(String size);

  /// No description provided for @syncFreeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Free space in Google Drive unknown'**
  String get syncFreeUnknown;

  /// No description provided for @syncNoFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders: every track is synced.'**
  String get syncNoFolders;

  /// No description provided for @syncStart.
  ///
  /// In en, this message translates to:
  /// **'Start sync'**
  String get syncStart;

  /// No description provided for @syncLine.
  ///
  /// In en, this message translates to:
  /// **'Sync: {status}'**
  String syncLine(String status);

  /// #122/AK2: starts the selection mode with check marks (track menu on touch devices)
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectTracks;

  /// #122: bar above the library while tracks are selected
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String selectionCount(int count);

  /// #122: tooltip of the «⋯» button in the selection bar
  ///
  /// In en, this message translates to:
  /// **'Actions for the selected tracks'**
  String get selectionActions;

  /// #122/AK6: ends the selection
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get selectionDone;

  /// #122/AK5: one question for several tracks
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 track?} other{Delete {count} tracks?}}'**
  String deleteTracksTitle(int count);

  /// #122/AK5
  ///
  /// In en, this message translates to:
  /// **'The tracks are removed from the app. The original files stay unchanged.'**
  String get deleteTracksText;

  /// #141: context menu of one or several selected tracks
  ///
  /// In en, this message translates to:
  /// **'Export as MP3 …'**
  String get exportEllipsis;

  /// #141: button of the folder dialog
  ///
  /// In en, this message translates to:
  /// **'Export here'**
  String get exportHere;

  /// #141/AK12: title of the progress dialog
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Exporting 1 track} other{Exporting {count} tracks}}'**
  String exportTitle(int count);

  /// #141/AK12: the track being exported
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}: {title}'**
  String exportProgress(int index, int total, String title);

  /// #141/AK13: result
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No track exported.} =1{1 track exported.} other{{count} tracks exported.}}'**
  String exportDone(int count);

  /// #141/AK12: result after cancelling
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Export cancelled. No track exported.} =1{Export cancelled. 1 track exported.} other{Export cancelled. {count} tracks exported.}}'**
  String exportCancelled(int count);

  /// #141: title of the result dialog
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportResultTitle;

  /// #141/AK14
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be loaded from the cloud.'**
  String exportFailedNotLoaded(String title);

  /// #141/AK13
  ///
  /// In en, this message translates to:
  /// **'«{title}»: this file cannot be read.'**
  String exportFailedFormat(String title);

  /// #141/AK16
  ///
  /// In en, this message translates to:
  /// **'«{title}»: MP3 is not available, the encoder is missing.'**
  String exportFailedEncoder(String title);

  /// #141/AK13
  ///
  /// In en, this message translates to:
  /// **'«{title}»: the file could not be written.'**
  String exportFailedWrite(String title);

  /// #141/AK13
  ///
  /// In en, this message translates to:
  /// **'«{title}» could not be exported.'**
  String exportFailed(String title);

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Armed'**
  String get armedSwitch;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Records the microphone by itself while you practise: as soon as you play, a recording starts, and it ends after a pause or with the space bar. Then «Armed» goes off, unless it is set to stay on for the next recording. The recordings go to the library into Recordings › date.'**
  String get armedSwitchTooltip;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Armed, waiting for sound'**
  String get armedWaiting;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Threshold, pause and end'**
  String get armedSettings;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Starts above'**
  String get armedThreshold;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Ends after a pause of'**
  String get armedSilence;

  /// #156: switch in the popover of «Armed»; off: armed again for the next recording
  ///
  /// In en, this message translates to:
  /// **'Switch off after a recording'**
  String get armedOffAfterTake;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Microphone level'**
  String get armedLevel;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'The level shows while «Armed» is on.'**
  String get armedLevelOff;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Another recording is running. Stop it, then switch «Armed» on.'**
  String get armedBusy;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Woodshed Player may not use the microphone, so «Armed» is off again. Grant access in System Settings › Privacy & Security › Microphone, then switch it on again.'**
  String get armedMicrophoneDenied;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'«Armed» could not start the microphone and is off again.'**
  String get armedFailed;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'«Armed» is on: the microphone records by itself while you practise. Switch «Armed» off to record with this button.'**
  String get recordingLockedByArmed;

  /// #147
  ///
  /// In en, this message translates to:
  /// **'{db} dBFS'**
  String armedThresholdValue(int db);

  /// #147
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String armedSilenceValue(int seconds);

  /// #147
  ///
  /// In en, this message translates to:
  /// **'Armed, recording {duration}'**
  String armedRecordingLabel(String duration);

  /// #148: the help page and its item in the Help menu of the Mac
  ///
  /// In en, this message translates to:
  /// **'Woodshed Player Help'**
  String get helpTitle;

  /// #148: the overview of the shortcuts (dialog, menu item, help section)
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get helpShortcutsTitle;

  /// No description provided for @helpShortcutsShow.
  ///
  /// In en, this message translates to:
  /// **'Show keyboard shortcuts'**
  String get helpShortcutsShow;

  /// #148: group of the shortcuts that work in every area
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get helpShortcutsGeneral;

  /// No description provided for @helpShortcutsPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice and Metronome'**
  String get helpShortcutsPractice;

  /// #148: names of keys in the shortcut overview
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get helpKeyEscape;

  /// No description provided for @helpKeyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get helpKeyDelete;

  /// No description provided for @helpKeyBackspace.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get helpKeyBackspace;

  /// #148: a click with a modifier, as in ⇧-click
  ///
  /// In en, this message translates to:
  /// **'click'**
  String get helpKeyClick;

  /// #148: what a shortcut does, one line of the overview each
  ///
  /// In en, this message translates to:
  /// **'Switch to Player, Practice, Metronome'**
  String get helpShortcutSwitchArea;

  /// No description provided for @helpShortcutOpen.
  ///
  /// In en, this message translates to:
  /// **'Add tracks'**
  String get helpShortcutOpen;

  /// No description provided for @helpShortcutSearch.
  ///
  /// In en, this message translates to:
  /// **'Search the library'**
  String get helpShortcutSearch;

  /// No description provided for @helpShortcutPlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play / pause'**
  String get helpShortcutPlayPause;

  /// No description provided for @helpShortcutShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle on / off'**
  String get helpShortcutShuffle;

  /// No description provided for @helpShortcutRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat: off, list, track'**
  String get helpShortcutRepeat;

  /// No description provided for @helpShortcutMute.
  ///
  /// In en, this message translates to:
  /// **'Mute on / off'**
  String get helpShortcutMute;

  /// No description provided for @helpShortcutPreviousNext.
  ///
  /// In en, this message translates to:
  /// **'Previous / next track'**
  String get helpShortcutPreviousNext;

  /// No description provided for @helpShortcutSeek.
  ///
  /// In en, this message translates to:
  /// **'15 s back / forward'**
  String get helpShortcutSeek;

  /// No description provided for @helpShortcutVolume.
  ///
  /// In en, this message translates to:
  /// **'Louder / quieter'**
  String get helpShortcutVolume;

  /// No description provided for @helpShortcutPracticePlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play / pause the track (Practice), start / stop the metronome (Metronome)'**
  String get helpShortcutPracticePlayPause;

  /// No description provided for @helpShortcutMetronome.
  ///
  /// In en, this message translates to:
  /// **'Metronome on / off'**
  String get helpShortcutMetronome;

  /// No description provided for @helpShortcutTap.
  ///
  /// In en, this message translates to:
  /// **'Tap tempo'**
  String get helpShortcutTap;

  /// No description provided for @helpShortcutSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed slower / faster'**
  String get helpShortcutSpeed;

  /// No description provided for @helpShortcutBpm.
  ///
  /// In en, this message translates to:
  /// **'Metronome +1 / −1 BPM'**
  String get helpShortcutBpm;

  /// No description provided for @helpShortcutBpm10.
  ///
  /// In en, this message translates to:
  /// **'Metronome +10 / −10 BPM'**
  String get helpShortcutBpm10;

  /// No description provided for @helpShortcutLoopStart.
  ///
  /// In en, this message translates to:
  /// **'Loop start at the playhead'**
  String get helpShortcutLoopStart;

  /// No description provided for @helpShortcutLoopEnd.
  ///
  /// In en, this message translates to:
  /// **'Loop end at the playhead'**
  String get helpShortcutLoopEnd;

  /// No description provided for @helpShortcutDeleteTrack.
  ///
  /// In en, this message translates to:
  /// **'Delete the loaded track (asks first)'**
  String get helpShortcutDeleteTrack;

  /// No description provided for @helpShortcutEndSelection.
  ///
  /// In en, this message translates to:
  /// **'End the selection, empty the search'**
  String get helpShortcutEndSelection;

  /// No description provided for @helpShortcutDeleteSelection.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected tracks (asks first)'**
  String get helpShortcutDeleteSelection;

  /// No description provided for @helpShortcutRangeClick.
  ///
  /// In en, this message translates to:
  /// **'Select the tracks up to here'**
  String get helpShortcutRangeClick;

  /// No description provided for @helpShortcutToggleClick.
  ///
  /// In en, this message translates to:
  /// **'Select or deselect a track'**
  String get helpShortcutToggleClick;

  /// #148: the sections of the help; a body has paragraphs separated by an empty line
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get helpAreasTitle;

  /// No description provided for @helpAreasBody.
  ///
  /// In en, this message translates to:
  /// **'Woodshed Player has three areas: Player for your library and simple playback, Practice for the waveform, loop, tempo and speed trainer, and Metronome with all its settings.\n\nSwitch with “Player | Practice | Metronome” at the top of the window, on the phone with the tab bar at the bottom, or with the keyboard. Switching stops neither the track nor the metronome; position, loop and tempo stay. A dot on a tab shows what is playing. If something plays in another area, a mini bar shows it and starts or stops it with a tap.\n\nOn the desktop the library stays beside the player. On the tablet the button “Library” opens it in every area. After a restart the app opens the area you chose last.'**
  String get helpAreasBody;

  /// No description provided for @helpPlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get helpPlayerTitle;

  /// No description provided for @helpPlayerBody.
  ///
  /// In en, this message translates to:
  /// **'The player shows cover, title, a progress bar and the volume. Below it are the controls: Shuffle, Previous, Play/Pause, Next and Repeat.\n\nShuffle plays every track of the list once per round. Previous goes back to the start of the track, within its first 3 seconds to the track before. Next goes to the next track. Repeat switches between off, the list and the track (shown with a small 1); a dot shows that it is on.\n\nA track plays within the list, folder or playlist you chose it from.'**
  String get helpPlayerBody;

  /// No description provided for @helpLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get helpLibraryTitle;

  /// No description provided for @helpLibraryBody.
  ///
  /// In en, this message translates to:
  /// **'Add tracks with + at the top of the library, or drag audio files into the window (Mac and browser); dropped on a folder or a playlist, they go there. Each file is stored only once, recognised by its content.\n\nFolders: “New folder” in the menu with the three dots at the top of the library creates one at the top level, “New subfolder …” in the menu of a folder one inside it, as deep as you like. A click opens or closes a folder. Drag tracks or whole folders onto a folder to move them (on iPhone and iPad press and hold first). “Delete folder” also deletes its subfolders; the tracks stay in the library under “No folder”.\n\nSort the library with the sort button, search it with the search field.\n\nThe menu of a track (right click or the three dots) edits title and artist (only in the library, the audio file stays unchanged), moves it to a folder, adds it to a playlist and deletes it after asking.\n\nSelect several tracks with ⌘-click or ⇧-click (Ctrl-click outside Apple); on iPhone and iPad press and hold a track or choose “Select”. The selected tracks can be dragged, added to a playlist, moved or deleted together.\n\nPlaylists are lists of tracks in their own order. + beside “Playlists” creates one; add tracks by dragging them onto it or with “Add to playlist”. “Play” plays its tracks one after the other.'**
  String get helpLibraryBody;

  /// No description provided for @helpPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get helpPracticeTitle;

  /// No description provided for @helpPracticeBody.
  ///
  /// In en, this message translates to:
  /// **'The waveform shows the whole track at the top (a tap jumps there) and below it the part around the loop or the playhead.\n\nLoop: “S here” and “E here” set start and end at the playhead, the keys S and E do the same while it plays. Drag the markers S and E in the waveform, or type the times as mm:ss.d. The loop bar also has “To loop start”, “Whole track” and loop on/off. Every track remembers its loop and tempo.\n\nTempo: from 0.1× to 2× with the slider or the quick choices. The pitch stays the same.\n\nTrim start and end: “Trim start and end …” in the menu of a track. Drag the two handles or type the times, check with “Listen”, then “Trim …”. The audio file really gets shorter; this cannot be undone.'**
  String get helpPracticeBody;

  /// No description provided for @helpMetronomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Metronome'**
  String get helpMetronomeTitle;

  /// No description provided for @helpMetronomeBody.
  ///
  /// In en, this message translates to:
  /// **'The metronome runs from 20 to 300 BPM: −/+ (hold to repeat), the slider, or tap the tempo with “Tap”. Choose the time signature (4/4, 3/4, 2/4, 6/8) and the subdivision (quarters, eighths, triplets, sixteenths); a change takes effect at once. The track and the metronome never play at the same time.\n\nAutomatic tempo increase: by bars (start and target BPM, step, every how many bars) or by time (start and target BPM over 1 to 60 minutes). At the target it starts again at the start BPM.\n\nRamp-up by passes, in Practice: the speed of the track rises step by step with the passes through the loop, for example from 60 % to 100 %, +5 % every 10 passes. A pass counts at the jump from the loop end to the start. The slider symbol opens its settings.'**
  String get helpMetronomeBody;

  /// No description provided for @helpSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get helpSyncTitle;

  /// No description provided for @helpSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Sync is off until you choose it. Then it keeps library, settings and audio files the same on your devices: through Google Drive with your Google account, where the app sees only the files it creates itself, or directly between your paired devices without an account. The direct connection comes with a later version.\n\nThe line “Sync: …” at the bottom of the library opens the settings: Off or Google Drive, sign in or out, sync now, restore a backup.\n\nWithout an account and without paired devices, the app makes no connection: everything stays on this device.'**
  String get helpSyncBody;

  /// No description provided for @helpAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance and language'**
  String get helpAppearanceTitle;

  /// No description provided for @helpAppearanceBody.
  ///
  /// In en, this message translates to:
  /// **'Choose System, Light or Dark under “Appearance” in the menu with the three dots at the top of the library. System follows the setting of your device, also while the app runs.\n\nThe app follows the language of your system: English or German, with any other language English. Numbers and sizes are written the way of the language, and on the Mac the menu bar changes with it.'**
  String get helpAppearanceBody;

  /// No description provided for @helpRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get helpRecordingTitle;

  /// No description provided for @helpRecordingBody.
  ///
  /// In en, this message translates to:
  /// **'“Record” at the top right starts and stops a recording. The menu beside it chooses the source for this device: system audio (macOS 14.2 or later; the player and the metronome are left out) or the microphone. The recording is saved losslessly as FLAC and appears in the library as a new track, named after date and time. The first time, macOS asks for permission.\n\nArmed: in Practice and Metronome, the switch “Armed” records from the microphone by itself. As soon as the level rises above the threshold, a recording starts, 1 second early; after a pause of the set length it ends. Space plays or pauses as usual and also ends a running recording. Then “Armed” goes off; to keep it armed for the next recording, switch off “Switch off after a recording” in its settings. Each recording lands in the library in the folder Recordings › date. The arrow beside the switch sets threshold, pause and whether it goes off after a recording. While “Armed” is on, “Record” is locked.'**
  String get helpRecordingBody;

  /// No description provided for @helpRecordingBodyBrowser.
  ///
  /// In en, this message translates to:
  /// **'“Record” at the top right starts and stops a recording through the microphone. The recording is saved losslessly as FLAC in the storage of this browser and appears in the library as a new track, named after date and time. The first time, the browser asks whether this website may use the microphone; if it is refused, allow it in the browser\'s site settings. If the app goes to the background or the screen is locked, the recording ends and is saved; while recording, the screen stays on.\n\nArmed: in Practice and Metronome, the switch “Armed” records from the microphone by itself. As soon as the level rises above the threshold, a recording starts, 1 second early; after a pause of the set length it ends. Space plays or pauses as usual and also ends a running recording. Then “Armed” goes off; to keep it armed for the next recording, switch off “Switch off after a recording” in its settings. Each recording lands in the library in the folder Recordings › date. The arrow beside the switch sets threshold, pause and whether it goes off after a recording. While “Armed” is on, “Record” is locked; in the background “Armed” goes off.'**
  String get helpRecordingBodyBrowser;

  /// No description provided for @helpExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export as MP3'**
  String get helpExportTitle;

  /// No description provided for @helpExportBody.
  ///
  /// In en, this message translates to:
  /// **'“Export as MP3 …” in the menu of a track, or of several selected tracks, writes them as MP3 files into a folder you choose, named “Title - Artist - Year.mp3”, with title, artist, album and year as tags. Nothing is overwritten.\n\nMP3 files are taken over without new encoding; WAV, FLAC, M4A and recordings are encoded at 192 kbit/s. The original file is exported; tempo and loop do not change it.'**
  String get helpExportBody;

  /// No description provided for @helpCommandLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get helpCommandLineTitle;

  /// No description provided for @helpCommandLineBody.
  ///
  /// In en, this message translates to:
  /// **'The program of the app is also its command line. Copy the script tools/woodshed from the source code into a folder of your search path, for example ~/bin/woodshed.\n\nwoodshed play --title \"<title>\" plays a track of the library. woodshed record waits for the first sound, records and stops by itself after a pause. woodshed --help lists every command and option.\n\nThe command talks only to the app on the same Mac, never over the network.'**
  String get helpCommandLineBody;

  /// No description provided for @helpWebTitle.
  ///
  /// In en, this message translates to:
  /// **'Web app'**
  String get helpWebTitle;

  /// No description provided for @helpWebBody.
  ///
  /// In en, this message translates to:
  /// **'Install: on iPhone and iPad tap Share, then “Add to Home Screen”; on Android use the menu of the browser. The app then starts like any other.\n\nWithout a connection: after the first visit the app also starts offline. A new version replaces the old one at the next start with a connection.\n\nAudio cache: with sync, the audio files on this device have a limit, 2 GB unless you change it; a tap on the storage line at the bottom of the library sets it. Above it, the tracks not played for the longest time lose their file on this device if it is in the cloud. They stay in the library as “Only in the cloud” and load again when played. “Keep offline” in the menu of a track keeps its file.'**
  String get helpWebBody;

  /// No description provided for @helpShortcutsBody.
  ///
  /// In en, this message translates to:
  /// **'Most functions have a keyboard shortcut. The overview lists them all, grouped by area; the key ? opens it at any time, except while you type in a text field. Shortcuts with ⌘ use Ctrl outside Apple.'**
  String get helpShortcutsBody;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'The system does not allow the microphone.'**
  String get recordingErrorAccessDenied;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'Windows does not let Woodshed Player use the microphone. Switch on “Microphone access” and “Let desktop apps access your microphone” in Settings › Privacy & security › Microphone, then start the recording again.'**
  String get recordingMicrophoneDeniedWindows;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'The system does not let Woodshed Player use the microphone. Check in the sound settings of the system that the input device may be used, then start the recording again.'**
  String get recordingMicrophoneDeniedLinux;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'Only silence is coming from the microphone. Check the input device in Settings › System › Sound › Input.'**
  String get recordingMicrophoneSilentWindows;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'Only silence is coming from the microphone. Check the input device and its volume in the sound settings of the system.'**
  String get recordingMicrophoneSilentLinux;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'Windows does not let Woodshed Player use the microphone, so «Armed» is off again. Switch on “Microphone access” and “Let desktop apps access your microphone” in Settings › Privacy & security › Microphone, then switch it on again.'**
  String get armedMicrophoneDeniedWindows;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'The system does not let Woodshed Player use the microphone, so «Armed» is off again. Check in the sound settings of the system that the input device may be used, then switch it on again.'**
  String get armedMicrophoneDeniedLinux;

  /// #162
  ///
  /// In en, this message translates to:
  /// **'“Record” at the top right starts and stops a recording through the microphone (the default input device of the system). The recording is saved losslessly as FLAC and appears in the library as a new track, named after date and time. Without an input device there is no “Record”. If Windows does not allow the microphone, switch it on in Settings › Privacy & security › Microphone, also for desktop apps.\n\nArmed: in Practice and Metronome, the switch “Armed” records from the microphone by itself. As soon as the level rises above the threshold, a recording starts, 1 second early; after a pause of the set length it ends. Space plays or pauses as usual and also ends a running recording. Then “Armed” goes off; to keep it armed for the next recording, switch off “Switch off after a recording” in its settings. Each recording lands in the library in the folder Recordings › date. The arrow beside the switch sets threshold, pause and whether it goes off after a recording. While “Armed” is on, “Record” is locked.'**
  String get helpRecordingBodyDesktop;
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
