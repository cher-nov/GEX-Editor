unit GmExtension;

{
  gmextension.pas
  Support for GameMaker GED/GEX/DAT file formats.
  Part of the "GEX Editor" project.

  Written by Dmitry D. Chernov aka Black Doomer.
}

{$MODE OBJFPC}
{$LONGSTRINGS ON}

{$INLINE ON}
{$ASSERTIONS ON}
{$RANGECHECKS ON}

{$WARN CONSTRUCTING_ABSTRACT OFF}

// TODO: Add consistency checks for TGmExtValueType, TGmExtInvokeType
//       and (maybe) TGmExtContentKind, since $RANGECHECKS doesn't emit
//       an exception if a value is out of range on typecast (why?).

// TODO: Mark some classes with 'abstract' and 'sealed' specifiers?

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
interface
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

uses
  SysUtils, Classes, fgl, ZStream,
  GmKryptStream;

const
  cGmExtVersionDefault = 700;
  cGmExtVersionGEX = 701;

////////////////////////////////////////////////////////////////////////////////////////////////////
type

  // This is the base hierarchy class for this unit. Its goal is to provide correct class names for
  // validation asserts, avoiding the necessity to use the ugly helper class for the whole TObject,
  // and create the ability for user to inherit its own classes if necessary.
  TGmExtObject = class
  strict protected
    class procedure CommonAssert( aCondition: Boolean; const aMessage: String ); inline;
    class function EnsureCryptoStream( aClass: TGmKryptStreamClass;
      var aStream: TStream ): TCustomGmKryptStream; inline;
  end;

  // This is the abstract interface class for any extension data that can be read or written into
  // the TStream. It serves to avoid the necessity for unit-wide friendship (i.e. 'private' and
  // 'protected' over their 'strict' versions) between partial entry classes (actually the
  // TGmExtFileEntry and TGmExtContent). With this approach we need to cast instances explicitly to
  // TGmExtEntity / TGmExtEntry every time we want to access their protected methods.
  TGmExtEntity = class( TGmExtObject )
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); virtual; abstract;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); virtual; abstract;

    procedure ReadEntityGEX( aStream: TStream ); virtual; abstract;
    procedure WriteEntityGEX( aStream: TStream; aOptimize: Boolean ); virtual; abstract;    
  end;

  TGmExtEntry = class( TGmExtEntity )
  strict protected
    fRevision : LongInt;
  public
    constructor Create();
    procedure LoadFromStream( aStream: TStream );
    procedure SaveToStream( aStream: TStream; aForceOptimize: Boolean );
    procedure Serialize( aStream: TStream; aForceRevision: LongInt );
    property Revision: LongInt read fRevision write fRevision;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////

  TGmExtValueType = (
    gex_vtString = 1,
    gex_vtReal = 2
  );

  TGmExtInvokeType = (
    gex_itStdcall = 11,
    gex_itCdecl = 12
  );

  RGmExtFuncArgCount = 0..16;
  TGmExtFunctionClass = class of TGmExtFunction;

  TGmExtFunction = class( TGmExtEntry )
  strict private
    fName : String;
    fSymbol : String;  // if empty, GM uses function name instead
    fHelpLine : String;
    fHidden : Boolean;
  strict protected
    fArgCount : RGmExtFuncArgCount;

    procedure ReadInvokeType( aStream: TStream ); virtual; abstract;
    procedure WriteInvokeType( aStream: TStream ); virtual; abstract;
    procedure ReadArgCount( aStream: TStream ); virtual; abstract;
    procedure WriteArgCount( aStream: TStream ); virtual; abstract;

    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    procedure AfterConstruction(); override;
    property Name: String read fName write fName;
    property Symbol: String read fSymbol write fSymbol;
    property HelpLine: String read fHelpLine write fHelpLine;
    property Hidden: Boolean read fHidden write fHidden;
    property ArgCount: RGmExtFuncArgCount read fArgCount write fArgCount;
  end;

  TGmExtFuncNative = class( TGmExtFunction )
  strict private
    fArgTypes : array[RGmExtFuncArgCount] of TGmExtValueType;
    fInvokeType : TGmExtInvokeType;
    fResultType : TGmExtValueType;

    function GetArgType( aIndex: RGmExtFuncArgCount ): TGmExtValueType;
    procedure SetArgType( aIndex: RGmExtFuncArgCount; aValue: TGmExtValueType );
  strict protected
    procedure ReadInvokeType( aStream: TStream ); override;
    procedure WriteInvokeType( aStream: TStream ); override;
    procedure ReadArgCount( aStream: TStream ); override;
    procedure WriteArgCount( aStream: TStream ); override;

    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    procedure AfterConstruction(); override;
    property ResultType: TGmExtValueType read fResultType write fResultType;
    property InvokeType: TGmExtInvokeType read fInvokeType write fInvokeType;
    property ArgTypes[i: RGmExtFuncArgCount]: TGmExtValueType
      read GetArgType write SetArgType;
  end;

  TGmExtFuncScript = class( TGmExtFunction )
  strict private
    fArgCountAny : Boolean;
  strict protected
    procedure ReadInvokeType( aStream: TStream ); override;
    procedure WriteInvokeType( aStream: TStream ); override;
    procedure ReadArgCount( aStream: TStream ); override;
    procedure WriteArgCount( aStream: TStream ); override;

    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    property ArgCountAny: Boolean read fArgCountAny write fArgCountAny;
  end;

  TGmExtConstant = class( TGmExtEntry )
  strict private
    fName : String;
    fValue : String;
    fHidden : Boolean;
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    property Name: String read fName write fName;
    property Value: String read fValue write fValue;
    property Hidden: Boolean read fHidden write fHidden;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////

  // FIXME: that's ugly, RGmExtContentKind should be actually
  //        defined as Low(TGmExtContentKind)..High(TGmExtContentKind)
  RGmExtContentKind = 1..4;
  TGmExtContentKind = (
    gex_ckLibraryNative = Low(RGmExtContentKind),
    gex_ckLibraryScript,
    gex_ckBinaryPlugin,
    gex_ckBinarySimple
  );

  TGmExtFunctionList = specialize TFPGObjectList<TGmExtFunction>;
  TGmExtConstantList = specialize TFPGObjectList<TGmExtConstant>;

  TGmExtContentClass = class of TGmExtContent;
  TGmExtContent = class;

  TGmExtDataEntry = class( TGmExtEntry )
  strict private
    fName : String;
    fSource : String;  // not necessarily an URI (URL / URN), but any string specifying the source
    fContent : TGmExtContent;
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    constructor Create( aContent: TGmExtContent = nil );
    property Name: String read fName write fName;
    property Source: String read fSource write fSource;
    property Content: TGmExtContent read fContent;
  end;

  TGmExtContent = class( TGmExtEntity )
  strict private
    fEntry : TGmExtDataEntry;
  public
    constructor Create( aEntry: TGmExtDataEntry = nil );
    destructor Destroy(); override;
    class function Kind(): TGmExtContentKind; virtual; abstract;
    property Entry: TGmExtDataEntry read fEntry;
  end;

  // Base class for native libraries and GM scripts
  TGmExtLibrary = class( TGmExtContent )
  strict private
    fInitFunction : String;
    fExitFunction : String;
    fFunctionList : TGmExtFunctionList;
    fConstantList : TGmExtConstantList;
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    procedure AfterConstruction(); override;
    procedure BeforeDestruction(); override;
    class function FunctionClass(): TGmExtFunctionClass; virtual; abstract;
    property InitFunction: String read fInitFunction write fInitFunction;
    property ExitFunction: String read fExitFunction write fExitFunction;
    property Functions: TGmExtFunctionList read fFunctionList;
    property Constants: TGmExtConstantList read fConstantList;
  end;

  // Base class for GM action libraries and simple files
  TGmExtBinary = class( TGmExtContent )
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  end;

  // Kind: SYS
  TGmExtLibNative = class( TGmExtLibrary )
  public
    class function Kind(): TGmExtContentKind; override;
    class function FunctionClass(): TGmExtFunctionClass; override;
  end;

  // Kind: GML
  TGmExtLibScript = class( TGmExtLibrary )
  public
    class function Kind(): TGmExtContentKind; override;
    class function FunctionClass(): TGmExtFunctionClass; override;
  end;

  // Kind: LIB
  TGmExtBinPlugin = class( TGmExtBinary )
  public
    class function Kind(): TGmExtContentKind; override;
  end;

  // Kind: BIN
  TGmExtBinSimple = class( TGmExtBinary )
  public
    class function Kind(): TGmExtContentKind; override;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////

  TGmExtContentList = specialize TFPGObjectList<TGmExtContent>;

  TGmExtPrototype = class( TGmExtEntry )
  strict private
    fName : String;
    fAuthor : String;
    fVersion : String;
    fDate : String;
    fLicense : String;
    fDescription : String;
    fHelpFile : String;
    fTempFolder : String;
    fDependencies : TStringList;
    fHidden : Boolean;
    fEditable : Boolean;
    fContentList : TGmExtContentList;
  strict protected
    procedure ReadEntityDefault( aStream: TStream ); override;
    procedure WriteEntityDefault( aStream: TStream; aOptimize: Boolean ); override;
  public
    procedure AfterConstruction(); override;
    procedure BeforeDestruction(); override;
    property Name: String read fName write fName;
    property Author: String read fAuthor write fAuthor;
    property Version: String read fVersion write fVersion;
    property Date: String read fDate write fDate;
    property License: String read fLicense write fLicense;
    property Description: String read fDescription write fDescription;
    property HelpFile: String read fHelpFile write fHelpFile;
    property TempFolder: String read fTempFolder write fTempFolder;
    property Dependencies: TStringList read fDependencies;
    property Hidden: Boolean read fHidden write fHidden;
    property Editable: Boolean read fEditable write fEditable;
    property Contents: TGmExtContentList read fContentList;
  end;

  TGmExtPackage = class( TGmExtEntry )
  strict private
    fPrototype : TGmExtPrototype;
    fKeySeed : LongInt;
  strict protected
    procedure ReadEntityGEX( aStream: TStream ); override;
    procedure WriteEntityGEX( aStream: TStream; aOptimize: Boolean ); override;
  public
    constructor Create();
    procedure AfterConstruction(); override;
    procedure BeforeDestruction(); override;
    property Prototype: TGmExtPrototype read fPrototype;
    property KeySeed: LongInt read fKeySeed write fKeySeed;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////

  TGmExtStreamList = specialize TFPGObjectList<TStream>;

  // The ownership of the returned TStream will be transferred to the calling class. If you want to
  // avoid this (e.g. to read from an already opened and being in-use network connection), you
  // should wrap it in TOwnerStream with .SourceOwner parameter set to False and return it instead.
  TGmExtStreamBuilderProc = function(
    aName: String;
    var aSource: String
  ): TStream;  // return 'nil' to skip

  TGmExtFile = class( TGmExtObject )
  strict protected
    fStreamList : TGmExtStreamList;

    procedure ReadStreams( aSource: TStream );
    procedure WriteStreams( aTarget: TStream; aZlibLevel: TCompressionLevel );
  public
    procedure AfterConstruction(); override;
    procedure BeforeDestruction(); override;
    property StreamList: TGmExtStreamList read fStreamList;
  end;

  TGmExtFileDAT = class( TGmExtFile )
  strict private
    fKeySeed : LongInt;
  public
    procedure AfterConstruction(); override;
    procedure LoadFromStream( aStream: TStream );
    procedure SaveToStream( aStream: TStream; aZlibLevel: TCompressionLevel = clDefault );
    property KeySeed: LongInt read fKeySeed write fKeySeed;
  end;

  TGmExtFileGEX = class( TGmExtFile )
  strict private
    fPackage : TGmExtPackage;

    function AppendStream( aName: String; aSource: String;
      cbStreamBuilder: TGmExtStreamBuilderProc ): String; inline;
  public
    procedure AfterConstruction(); override;
    procedure BeforeDestruction(); override;
    procedure LoadFromStream( aStream: TStream; cbStreamBuilder: TGmExtStreamBuilderProc );
    procedure SaveToStream( aStream: TStream; cbStreamBuilder: TGmExtStreamBuilderProc;
      aForceOptimize: Boolean = False; aZlibLevel: TCompressionLevel = clDefault );
    property Package: TGmExtPackage read fPackage;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////

  TGmExtStreamHelper = class helper for TStream
  // Methods are 'protected' so that they can be called from this module without cluttering up the
  // global TStream namespace. If for some unknown reason you want to use these methods in your own
  // code, then inherit another helper from this one.
  protected
    function ReadGmInteger(): LongInt; inline;
    function ReadGmString(): String; inline;

    procedure WriteGmInteger( aValue: LongInt ); inline;
    procedure WriteGmInteger( aValue: LongInt; aSkip: Boolean; aRequired: Boolean;
      aFallback: LongInt = 0 ); inline; overload;

    procedure WriteGmString( aValue: String ); inline;
    procedure WriteGmString( aValue: String; aSkip: Boolean; aRequired: Boolean;
      aFallback: String = '' ); inline; overload;
  end;

const
  cGmExtContentTypes : array[RGmExtContentKind] of TGmExtContentClass = (
    TGmExtLibNative, TGmExtLibScript, TGmExtBinPlugin, TGmExtBinSimple
  );

function GmExtRandomTempFolder(): String;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

uses
  LazFileUtils;

const
  cGmExtSignatureGEX = 1234321;
  cGmExtArgNumArbitrary = -1;
  cGmExtScriptInvokeType = 2;

////////////////////////////////////////////////////////////////////////////////////////////////////

function GmExtRandomTempFolder(): String;
begin
  Result := Format( 'temp%.3d', [Random(1000)] );
end;

// this is awkward and not thread-safe
function ExtractFileExtDelphi( const aFileName: String ): String; inline;
var
  CurrentState : Boolean;
begin
  CurrentState := FirstDotAtFileNameStartIsExtension;
  FirstDotAtFileNameStartIsExtension := True;
  Result := ExtractFileExt( aFileName );
  FirstDotAtFileNameStartIsExtension := CurrentState;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtObject
////////////////////////////////////////////////////////////////////////////////////////////////////

class procedure TGmExtObject.CommonAssert( aCondition: Boolean; const aMessage: String );
begin
  Assert( aCondition, Format( '%s.'+LineEnding+'%s', [aMessage, ClassName()] ) );
end;

// We need this approach because GEX format is somewhat inconsistent: we need to encrypt / decrypt
// both the entries hierarchy and compressed data, but the key seed is specified in the header of
// the root entry (!) after the entry revision number (!!). Therefore, we create a crypto stream
// with an identical state, read / write the key seed from / to it and then initialize the cipher.
// This allows us to continue to use this stream to read / write the compressed data after
// processing the entries.
class function TGmExtObject.EnsureCryptoStream( aClass: TGmKryptStreamClass;
  var aStream: TStream ): TCustomGmKryptStream;
begin
  if aStream is aClass then begin
    TStream(Result) := aStream;
    CommonAssert( Result.IsIdenticalCrypto(), 'Stream is not set to an identical cipher state' );
    aStream := nil;
  end else begin
    Result := aClass.Create( aStream );
    aStream := Result;
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtEntry
////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TGmExtEntry.Create();
begin
  inherited;
  fRevision := cGmExtVersionDefault;
end;

procedure TGmExtEntry.LoadFromStream( aStream: TStream );
var
  KnownVersion : Boolean = True;
begin
  // Important design decision. To reset any non-essential data in the entry, it should be enough
  // to call .BeforeDestruction() followed by .AfterConstruction(). Therefore, we use constructors
  // and destructors to initialize and release the essential data ONLY, e.g. the revision number of
  // a TGmExtEntry (otherwise we'll get wrong value here) or the linked entry of a TGmExtContent.

  BeforeDestruction();
  AfterConstruction();

  fRevision := aStream.ReadGmInteger();

  try
    case fRevision of
    cGmExtVersionDefault:
      ReadEntityDefault( aStream );
    cGmExtVersionGEX:
      ReadEntityGEX( aStream );
    else
      KnownVersion := False;
    end;
  except
    on EAbstractError do
      KnownVersion := False;
  end;

  CommonAssert( KnownVersion, Format( 'Unsupported entry version (%d)', [fRevision] ) );
end;

procedure TGmExtEntry.SaveToStream( aStream: TStream; aForceOptimize: Boolean );
var
  RevisionValue : LongInt;
begin
  if aForceOptimize then
    RevisionValue := -Abs( fRevision )
  else
    RevisionValue := fRevision;

  Serialize( aStream, RevisionValue );
end;

procedure TGmExtEntry.Serialize( aStream: TStream; aForceRevision: LongInt );
var
  OptimizeEntry : Boolean;
  KnownVersion : Boolean = True;
begin
  OptimizeEntry := aForceRevision < 0;
  if OptimizeEntry then aForceRevision := -aForceRevision;
  aStream.WriteGmInteger( aForceRevision );

  try
    case aForceRevision of
    cGmExtVersionDefault:
      WriteEntityDefault( aStream, OptimizeEntry );
    cGmExtVersionGEX:
      WriteEntityGEX( aStream, OptimizeEntry );
    else
      KnownVersion := False;
    end;
  except
    on EAbstractError do
      KnownVersion := False;
  end;

  CommonAssert( KnownVersion, Format( 'Unknown entry version (%d)', [aForceRevision] ) );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFunction
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFunction.AfterConstruction();
begin
  inherited;
  fArgCount := Low(RGmExtFuncArgCount);
end;

procedure TGmExtFunction.ReadEntityDefault( aStream: TStream );
begin
  fName := aStream.ReadAnsiString();
  fSymbol := aStream.ReadAnsiString();
  ReadInvokeType( aStream );
  fHelpLine := aStream.ReadAnsiString();
  fHidden := Boolean( aStream.ReadGmInteger() );
  ReadArgCount( aStream );
end;

procedure TGmExtFunction.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
begin
  aStream.WriteGmString( fName );
  aStream.WriteGmString( fSymbol, aOptimize, fName <> fSymbol );

  WriteInvokeType( aStream );
  aStream.WriteGmString( fHelpLine, aOptimize, not fHidden );
  aStream.WriteGmInteger( LongInt(fHidden) );
  WriteArgCount( aStream );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFuncNative
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFuncNative.AfterConstruction();
var
  i : RGmExtFuncArgCount;
begin
  inherited;

  for i in RGmExtFuncArgCount do
    fArgTypes[i] := gex_vtReal;

  fInvokeType := gex_itStdcall;
  fResultType := gex_vtReal;
end;

function TGmExtFuncNative.GetArgType( aIndex: RGmExtFuncArgCount ): TGmExtValueType;
begin
  Result := fArgTypes[aIndex];
end;

procedure TGmExtFuncNative.SetArgType( aIndex: RGmExtFuncArgCount; aValue: TGmExtValueType );
begin
  fArgTypes[aIndex] := aValue;
end;

procedure TGmExtFuncNative.ReadInvokeType( aStream: TStream );
begin
  fInvokeType := TGmExtInvokeType( aStream.ReadGmInteger() );
end;

procedure TGmExtFuncNative.WriteInvokeType( aStream: TStream );
begin
  aStream.WriteGmInteger( LongInt(fInvokeType) );
end;

procedure TGmExtFuncNative.ReadArgCount( aStream: TStream );
begin
  fArgCount := aStream.ReadGmInteger();
end;

procedure TGmExtFuncNative.WriteArgCount( aStream: TStream );
begin
  aStream.WriteGmInteger( LongInt(fArgCount) );
end;

procedure TGmExtFuncNative.ReadEntityDefault( aStream: TStream );
var
  i : RGmExtFuncArgCount;
begin
  inherited;

  // Note: there are fields for 17 arguments, but only the first 4 are actually used.
  for i in RGmExtFuncArgCount do
    fArgTypes[i] := TGmExtValueType( aStream.ReadGmInteger() );

  fResultType := TGmExtValueType( aStream.ReadGmInteger() );
end;

procedure TGmExtFuncNative.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
var
  i : RGmExtFuncArgCount;
begin
  inherited;

  for i in RGmExtFuncArgCount do
    aStream.WriteGmInteger( LongInt(fArgTypes[i]) );

  aStream.WriteGmInteger( LongInt(fResultType) );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFuncScript
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFuncScript.ReadInvokeType( aStream: TStream );
var
  InvokeTypeValue : LongInt;
begin
  InvokeTypeValue := aStream.ReadGmInteger();

  // this fails for non-editable GM Windows Dialogs.ged from GameMaker 8
  //CommonAssert( InvokeTypeValue = cGmExtScriptInvokeType,
  //  Format( 'Unsupported calling convention for a GML script (%d)', [InvokeTypeValue] ) );
end;

procedure TGmExtFuncScript.WriteInvokeType( aStream: TStream );
begin
  aStream.WriteGmInteger( cGmExtScriptInvokeType );
end;

procedure TGmExtFuncScript.ReadArgCount( aStream: TStream );
var
  ArgNumValue : LongInt;
begin
  ArgNumValue := aStream.ReadGmInteger();
  fArgCountAny := ArgNumValue = cGmExtArgNumArbitrary;
  if fArgCountAny then
    ArgNumValue := Low(RGmExtFuncArgCount);
  fArgCount := ArgNumValue;
end;

procedure TGmExtFuncScript.WriteArgCount( aStream: TStream );
begin
  if fArgCountAny then
    aStream.WriteGmInteger( cGmExtArgNumArbitrary )
  else
    aStream.WriteGmInteger( LongInt(fArgCount) );
end;

procedure TGmExtFuncScript.ReadEntityDefault( aStream: TStream );
var
  i : RGmExtFuncArgCount;
begin
  inherited;

  for i in RGmExtFuncArgCount do
    aStream.ReadGmInteger();

  aStream.ReadGmInteger();
end;

procedure TGmExtFuncScript.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
var
  i : RGmExtFuncArgCount;
begin
  inherited;

  for i in RGmExtFuncArgCount do
    aStream.WriteGmInteger( LongInt(gex_vtReal) );

  aStream.WriteGmInteger( LongInt(gex_vtReal) );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtConstant
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtConstant.ReadEntityDefault( aStream: TStream );
begin
  fName := aStream.ReadAnsiString();
  fValue := aStream.ReadAnsiString();
  fHidden := Boolean( aStream.ReadGmInteger() );
end;

procedure TGmExtConstant.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
begin
  aStream.WriteGmString( fName );
  aStream.WriteGmString( fValue );
  aStream.WriteGmInteger( LongInt(fHidden) );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtDataEntry
////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TGmExtDataEntry.Create( aContent: TGmExtContent );
begin
  inherited Create();
  fContent := aContent;
end;

// GM4HTML5 1.0.218 (the last classic version) adds files into GEX in a somewhat strange way.
// First of all, it doesn't allow to specify file kind (like original ExtMaker does), instead
// trying by itself to determine their contents by filename extensions. But resulting kinds
// doesn't correspond neither to ExtMaker ones, nor to Resource Tree icons in the IDE. Next,
// GM4HTML5 allows to specify functions and constants for ANY file. So I provide a table here:
// =============================================================================================
// File:  .DLL  .DYLIB  .SO  .A  .JS  .GML  .LIB  .CHM  .HTM  .HTML  .TXT  .RTF  |  note: kind
// Kind:     1       0    0   0    5*    2     3     6*    0      0     0     0  |  4 is unused
// ---------------------------------------------------------------------------------------------
// Kind:     0      1        2        3       4      5       6      7,8,9,etc. | Resource Tree's
// Icon:    no    "DLL"    "GML"    "LIB"    no     "?"    "JS"     no         | icon labels
// ---------------------------------------------------------------------------------------------
// 5* : but in 39js.gex all kinds of .js files are 0, which's weird (maybe made on old GM4HTML5?)
// 6* : possibly related to "?" icon; filename also stated in <helpfile> XML field in .gmx file;
//      GM4HTML5 puts the .CHM into compiled .EXE 2 times: as a help file and as a regular file.
// =============================================================================================
// All of this information was obtained experimentally by adding files with different filename
// extensions, and manual editing of extension's .gmx file in the project tree.
// I decided to convert kind 0 to "Native library" because in case of a simple file, it wiil (at
// least, it should) contain zero values in library-related fields, so GM runner will trait it
// just like a regular simple file. But if it's a .JS like in 39js.gex (see note 5*), then we'll
// parse it correctly without losing any important data.
procedure TGmExtDataEntry.ReadEntityDefault( aStream: TStream );
var
  ContentKindValue : LongInt;
begin
  fName := aStream.ReadAnsiString();
  fSource := aStream.ReadAnsiString();

  ContentKindValue := aStream.ReadGmInteger();
  case ContentKindValue of
    0, 5: ContentKindValue := LongInt(gex_ckLibraryNative);
    6: ContentKindValue := LongInt(gex_ckBinarySimple);
  end;

  fContent := cGmExtContentTypes[RGmExtContentKind(ContentKindValue)].Create( Self );
  try
    // why FPC (Delphi?) can't guess about the common ancestor? :<
    (fContent as TGmExtEntity).ReadEntityDefault( aStream );
  except
    fContent.Destroy();
    raise;
  end;
end;

procedure TGmExtDataEntry.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
begin
  aStream.WriteGmString( fName );
  aStream.WriteGmString( fSource, aOptimize, False );
  aStream.WriteGmInteger( LongInt( fContent.Kind() ) );
  (fContent as TGmExtEntity).WriteEntityDefault( aStream, aOptimize );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtContent
////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TGmExtContent.Create( aEntry: TGmExtDataEntry );
begin
  inherited Create();
  if aEntry = nil then
    aEntry := TGmExtDataEntry.Create( Self );
  fEntry := aEntry;
end;

destructor TGmExtContent.Destroy();
begin
  fEntry.Free();
  inherited;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtBinary
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtBinary.ReadEntityDefault( aStream: TStream );
begin
  CommonAssert( aStream.ReadAnsiString() = '', 'Initialization function is not empty' );
  CommonAssert( aStream.ReadAnsiString() = '', 'Release function is not empty' );

  CommonAssert( aStream.ReadGmInteger() = 0, 'Number of functions is not 0' );
  CommonAssert( aStream.ReadGmInteger() = 0, 'Number of constants is not 0' );
end;

procedure TGmExtBinary.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
begin
  aStream.WriteGmString('');
  aStream.WriteGmString('');

  aStream.WriteGmInteger(0);
  aStream.WriteGmInteger(0);
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtLibrary
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtLibrary.AfterConstruction();
begin
  inherited;
  fFunctionList := TGmExtFunctionList.Create();
  fConstantList := TGmExtConstantList.Create();
end;

procedure TGmExtLibrary.BeforeDestruction();
begin
  FreeAndNil( fFunctionList );
  FreeAndNil( fConstantList );
  inherited;
end;

procedure TGmExtLibrary.ReadEntityDefault( aStream: TStream );
var
  NewFunc : TGmExtFunction;
  NewConst : TGmExtConstant;
  FuncCount : LongInt;
  ConstCount : LongInt;
  i : SizeInt;
begin
  fInitFunction := aStream.ReadAnsiString();
  fExitFunction := aStream.ReadAnsiString();

  // We add functions and constants before actual loading to
  // prevent possible memory leak on exception when doing that.

  FuncCount := aStream.ReadGmInteger();
  for i := 1 to FuncCount do begin
    NewFunc := FunctionClass().Create();
    fFunctionList.Add( NewFunc );
    NewFunc.LoadFromStream( aStream );
  end;

  ConstCount := aStream.ReadGmInteger();
  for i := 1 to ConstCount do begin
    NewConst := TGmExtConstant.Create();
    fConstantList.Add( NewConst );
    NewConst.LoadFromStream( aStream );
  end;
end;

procedure TGmExtLibrary.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
var
  iFunction : TGmExtFunction;
  iConstant : TGmExtConstant;
begin
  aStream.WriteGmString( fInitFunction );
  aStream.WriteGmString( fExitFunction );

  aStream.WriteGmInteger( fFunctionList.Count );
  for iFunction in fFunctionList do
    iFunction.SaveToStream( aStream, aOptimize );

  aStream.WriteGmInteger( fConstantList.Count );
  for iConstant in fConstantList do
    iConstant.SaveToStream( aStream, aOptimize );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtLibNative
////////////////////////////////////////////////////////////////////////////////////////////////////

class function TGmExtLibNative.Kind(): TGmExtContentKind;
begin
  Result := gex_ckLibraryNative;
end;

class function TGmExtLibNative.FunctionClass(): TGmExtFunctionClass;
begin
  Result := TGmExtFuncNative;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtLibScript
////////////////////////////////////////////////////////////////////////////////////////////////////

class function TGmExtLibScript.Kind(): TGmExtContentKind;
begin
  Result := gex_ckLibraryScript;
end;

class function TGmExtLibScript.FunctionClass(): TGmExtFunctionClass;
begin
  Result := TGmExtFuncScript;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtBinPlugin
////////////////////////////////////////////////////////////////////////////////////////////////////

class function TGmExtBinPlugin.Kind(): TGmExtContentKind;
begin
  Result := gex_ckBinaryPlugin;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtBinSimple
////////////////////////////////////////////////////////////////////////////////////////////////////

class function TGmExtBinSimple.Kind(): TGmExtContentKind;
begin
  Result := gex_ckBinarySimple;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtPrototype
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtPrototype.AfterConstruction();
begin
  inherited;
  fEditable := True;
  //fTempFolder := GmExtRandomTempFolder();
  fDependencies := TStringList.Create();
  fContentList := TGmExtContentList.Create();
end;

procedure TGmExtPrototype.BeforeDestruction();
begin
  FreeAndNil( fDependencies );
  FreeAndNil( fContentList );
  inherited;
end;

procedure TGmExtPrototype.ReadEntityDefault( aStream: TStream );
var
  UsesCount : LongInt;
  FileCount : LongInt;
  FileEntry : TGmExtDataEntry;
  i : Integer;
begin
  fEditable := Boolean( aStream.ReadGmInteger() );
  fName := aStream.ReadAnsiString();
  fTempFolder := aStream.ReadAnsiString();
  fVersion := aStream.ReadAnsiString();
  fAuthor := aStream.ReadAnsiString();
  fDate := aStream.ReadAnsiString();
  fLicense := aStream.ReadAnsiString();
  fDescription := aStream.ReadAnsiString();
  fHelpFile := aStream.ReadAnsiString();
  fHidden := Boolean( aStream.ReadGmInteger() );

  UsesCount := aStream.ReadGmInteger();
  for i := 1 to UsesCount do
    fDependencies.Add( aStream.ReadAnsiString() );

  FileCount := aStream.ReadGmInteger();
  for i := 1 to FileCount do begin
    FileEntry := TGmExtDataEntry.Create( nil );
    FileEntry.LoadFromStream( aStream );
    fContentList.Add( FileEntry.Content );
  end;
end;

procedure TGmExtPrototype.WriteEntityDefault( aStream: TStream; aOptimize: Boolean );
var
  iDependency : String;
  iContent : TGmExtContent;
begin
  aStream.WriteGmInteger( LongInt(fEditable), aOptimize, False, LongInt(False) );
  aStream.WriteGmString( fName );
  aStream.WriteGmString( fTempFolder );
  aStream.WriteGmString( fVersion );
  aStream.WriteGmString( fAuthor );
  aStream.WriteGmString( fDate );
  aStream.WriteGmString( fLicense );
  aStream.WriteGmString( fDescription );

  // GameMaker IDE opens help file through shell command, so original file extension is important.
  aStream.WriteGmString( fHelpFile, aOptimize, False, ExtractFileExtDelphi(fHelpFile) );

  aStream.WriteGmInteger( LongInt(fHidden) );

  aStream.WriteGmInteger( fDependencies.Count );
  for iDependency in fDependencies do
    aStream.WriteGmString( iDependency );

  aStream.WriteGmInteger( fContentList.Count );
  for iContent in fContentList do
    iContent.Entry.SaveToStream( aStream, aOptimize );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtPackage
////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TGmExtPackage.Create();
begin
  inherited;
  fRevision := cGmExtVersionGEX;
end;

procedure TGmExtPackage.AfterConstruction();
begin
  inherited;
  fPrototype := TGmExtPrototype.Create();
  fKeySeed := cGmKryptIdentityKeySeed;
end;

procedure TGmExtPackage.BeforeDestruction();
begin
  FreeAndNil( fPrototype );
  inherited;
end;

procedure TGmExtPackage.ReadEntityGEX( aStream: TStream );
var
  DecodeStream : TCustomGmKryptStream;
begin
  DecodeStream := EnsureCryptoStream( TGmKryptDecodeStream, aStream );

  try
    fKeySeed := DecodeStream.ReadGmInteger();
    DecodeStream.InitState( fKeySeed, False );
    fPrototype.LoadFromStream( DecodeStream );
  finally
    aStream.Free();
  end;
end;

procedure TGmExtPackage.WriteEntityGEX( aStream: TStream; aOptimize: Boolean );
var
  EncodeStream : TCustomGmKryptStream;
begin
  EncodeStream := EnsureCryptoStream( TGmKryptEncodeStream, aStream );

  try
    EncodeStream.WriteGmInteger( fKeySeed );
    EncodeStream.InitState( fKeySeed, False );
    fPrototype.SaveToStream( EncodeStream, aOptimize );
  finally
    aStream.Free();
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFile
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFile.AfterConstruction();
begin
  fStreamList := TGmExtStreamList.Create();
  inherited;
end;

procedure TGmExtFile.BeforeDestruction();
begin
  FreeAndNil( fStreamList );
  inherited;
end;

// TODO: Reimplement Zlib stream with DataLimit property to prevent excessive read
//       after stream end. This will make us able to get rid of MemoryStream here.
procedure TGmExtFile.ReadStreams( aSource: TStream );
var
  MemoryStream : TMemoryStream;
  UnpackStream : TDecompressionStream;
  PackedSize : LongInt;
  iStream : TStream;
begin
  MemoryStream := TMemoryStream.Create();

  try
    for iStream in fStreamList do begin
      PackedSize := aSource.ReadGmInteger();
      if iStream = nil then begin
        aSource.Seek( PackedSize, soFromCurrent );
        continue;
      end;

      MemoryStream.CopyFrom( aSource, PackedSize );
      MemoryStream.Position := 0;
      UnpackStream := TDecompressionStream.Create( MemoryStream );
  
      try
        iStream.CopyFrom( UnpackStream, 0 );
      finally
        UnpackStream.Destroy();
      end;

      MemoryStream.Clear();
    end;

  finally
    MemoryStream.Destroy();

  end;
end;

// There's an inconsistence in how a data block should be built. Since the size of
// a packed file is located before its contents, we must write it first in case of
// streamed output without Seek() to be used. But to obtain that size, we must firstly
// compress the whole file, determine its compressed size, write it and then output
// packed data. Only three options are available to overcome this (the used one is 1st):
// (1) Compress the whole file into the memory stream, then output its size and content.
// (2) Compress the whole file into the void but remember the size of a result, write it
// and then compress again with the same parameters, but output a result this time.
// (3) Skip 4 bytes, compress file into an output stream, seek back, write size and then
// seek forward after data been written (requires well-implemented Seek() on a TStream).
procedure TGmExtFile.WriteStreams( aTarget: TStream; aZlibLevel: TCompressionLevel );
var
  MemoryStream : TMemoryStream;
  PackStream : TCompressionStream;
  PackedSize : LongInt;
  iStream : TStream;
begin
  MemoryStream := TMemoryStream.Create();

  try
    for iStream in fStreamList do begin
      PackStream := TCompressionStream.Create( aZlibLevel, MemoryStream );
  
      try
        PackStream.CopyFrom( iStream, 0 );
      finally
        PackStream.Destroy();
      end;

      PackedSize := LongInt( MemoryStream.Size );
      aTarget.WriteGmInteger( PackedSize );
      MemoryStream.Position := 0;
      aTarget.CopyFrom( MemoryStream, PackedSize );
      MemoryStream.Clear();
    end;

  finally
    MemoryStream.Destroy();

  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFileDAT
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFileDAT.AfterConstruction();
begin
  inherited;
  fKeySeed := cGmKryptIdentityKeySeed;
end;

procedure TGmExtFileDAT.LoadFromStream( aStream: TStream );
var
  DecodeStream : TCustomGmKryptStream;
begin
  DecodeStream := EnsureCryptoStream( TGmKryptDecodeStream, aStream );

  try
    fKeySeed := DecodeStream.ReadGmInteger();
    DecodeStream.InitState( fKeySeed, False );
    ReadStreams( DecodeStream );
  finally
    aStream.Free();
  end;  
end;

procedure TGmExtFileDAT.SaveToStream( aStream: TStream; aZlibLevel: TCompressionLevel );
var
  EncodeStream : TCustomGmKryptStream;
begin
  EncodeStream := EnsureCryptoStream( TGmKryptEncodeStream, aStream );

  try
    EncodeStream.WriteGmInteger( fKeySeed );
    EncodeStream.InitState( fKeySeed, False );
    WriteStreams( EncodeStream, aZlibLevel );
  finally
    aStream.Free();
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtFileGEX
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TGmExtFileGEX.AfterConstruction();
begin
  inherited;
  fPackage := TGmExtPackage.Create();
end;

procedure TGmExtFileGEX.BeforeDestruction();
begin
  FreeAndNil( fPackage );
  inherited;
end;

procedure TGmExtFileGEX.LoadFromStream( aStream: TStream;
  cbStreamBuilder: TGmExtStreamBuilderProc );
var
  SignatureValue : LongInt;
  DecodeStream : TCustomGmKryptStream;
  ContentFileName : String;
  iContent : TGmExtContent;
begin
  SignatureValue := aStream.ReadGmInteger();
  CommonAssert( SignatureValue = cGmExtSignatureGEX,
    Format( 'Invalid package signature (%d)', [SignatureValue] ) );
  DecodeStream := EnsureCryptoStream( TGmKryptDecodeStream, aStream );

  try
    fPackage.LoadFromStream( DecodeStream );

    if Assigned( cbStreamBuilder ) then begin
      // The compressed data of a help file is stored in the beginning of the data block.
      if fPackage.Prototype.HelpFile <> '' then begin
        ContentFileName := ExtractFileNameOnly( fPackage.Prototype.HelpFile );
        if ContentFileName = '' then
          // TempFolder is the only filesystem-friendly name we can obtain here without sanitizing.
          ContentFileName := fPackage.Prototype.TempFolder;

        fPackage.Prototype.HelpFile := AppendStream(
          ContentFileName + ExtractFileExt( fPackage.Prototype.HelpFile ),
          fPackage.Prototype.HelpFile,
          cbStreamBuilder
        );
      end;

      for iContent in fPackage.Prototype.Contents do begin
        ContentFileName := ExtractFileName( iContent.Entry.Source );
        if ContentFileName = '' then
          ContentFileName := iContent.Entry.Name;
        iContent.Entry.Source := AppendStream( ContentFileName, iContent.Entry.Source,
          cbStreamBuilder );
      end;
    end;

    ReadStreams( DecodeStream );

  finally
    aStream.Free();
    fStreamList.Clear();

  end;
end;

procedure TGmExtFileGEX.SaveToStream( aStream: TStream; cbStreamBuilder: TGmExtStreamBuilderProc;
  aForceOptimize: Boolean; aZlibLevel: TCompressionLevel );
var
  EncodeStream : TCustomGmKryptStream;
  iContent : TGmExtContent;
begin
  aStream.WriteGmInteger( cGmExtSignatureGEX );
  EncodeStream := EnsureCryptoStream( TGmKryptEncodeStream, aStream );

  try
    fPackage.SaveToStream( EncodeStream, aForceOptimize );

    if Assigned( cbStreamBuilder ) then begin
      if fPackage.Prototype.HelpFile <> '' then
        fPackage.Prototype.HelpFile := AppendStream( ExtractFileName( fPackage.Prototype.HelpFile ),
          fPackage.Prototype.HelpFile, cbStreamBuilder );

      for iContent in fPackage.Prototype.Contents do
        iContent.Entry.Source := AppendStream( iContent.Entry.Name, iContent.Entry.Source,
          cbStreamBuilder );
    end;

    WriteStreams( EncodeStream, aZlibLevel );

  finally
    aStream.Free();
    fStreamList.Clear();

  end;
end;

function TGmExtFileGEX.AppendStream( aName: String; aSource: String;
  cbStreamBuilder: TGmExtStreamBuilderProc ): String;
begin
  Result := aSource;
  fStreamList.Add( cbStreamBuilder( aName, Result ) );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmExtStreamHelper
////////////////////////////////////////////////////////////////////////////////////////////////////

function TGmExtStreamHelper.ReadGmInteger(): LongInt;
begin
  Result := 0;  // shut up fpc
  ReadBuffer( Result, SizeOf(Result) );
end;

function TGmExtStreamHelper.ReadGmString(): String;
begin
  Result := ReadAnsiString();
end;

procedure TGmExtStreamHelper.WriteGmInteger( aValue: LongInt );
begin
  WriteBuffer( aValue, SizeOf(aValue) );
end;

procedure TGmExtStreamHelper.WriteGmInteger( aValue: LongInt; aSkip: Boolean; aRequired: Boolean;
  aFallback: LongInt );
begin
  if aSkip and not aRequired then
    aValue := aFallback;
  WriteGmInteger( aValue );
end;

procedure TGmExtStreamHelper.WriteGmString( aValue: String );
begin
  WriteAnsiString( aValue );
end;

procedure TGmExtStreamHelper.WriteGmString( aValue: String; aSkip: Boolean; aRequired: Boolean;
  aFallback: String );
begin
  if aSkip and not aRequired then
    aValue := aFallback;
  WriteGmString( aValue );
end;

end.

