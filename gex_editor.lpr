program gex_editor;

{$MODE OBJFPC}
{$LONGSTRINGS ON}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils, LazFileUtils,
  Classes, CustApp, ZStream,
  GmExtension;

type

  TApplication = class( TCustomApplication )
  private
    fExtension : TGmExtFileGEX;

  protected
    procedure DoRun(); override;

  public
    constructor Create( aOwner: TComponent ); override;
    destructor Destroy(); override;

    procedure ActionPrintUsage(); virtual;
    procedure ActionCompose(); virtual;
    procedure ActionDecompose(); virtual;
  end;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure Report( aStage, aName: String ); inline;
begin
  WriteLn( aStage, ' ''', aName, ''' ...' );
end;

// TODO: Sanitize Windows special chars and identifiers like PRN from the filename.
// https://forum.lazarus.freepascal.org/index.php?topic=16862.0
function MakeSafeFileName( aName: String ): String;
var
  Extension : String;
  SuffixValue : Integer = 0;
begin
  Result := aName;

  aName := ExtractFileNameWithoutExt( Result );
  Extension := ExtractFileExt( Result );

  while FileExists( Result ) do begin
    SuffixValue += 1;
    Result := aName + '_' + IntToStr( SuffixValue ) + Extension;
  end;
end;

function MakeSafeFolderName( aName: String ): String;
var
  SuffixValue : Integer = 0;
begin
  Result := aName;
  while DirectoryExists( Result ) do begin
    SuffixValue += 1;
    Result := aName + '_' + IntToStr( SuffixValue );
  end;
end;

function CB_PrepareWritingStreams( aName: String; var aSource: String ): TStream;
begin
  aSource := MakeSafeFilename( aName );
  Report( 'saving', aSource );
  Result := TFileStream.Create( aSource, fmCreate );
end;

function CB_PrepareReadingStreams( aName: String; var aSource: String ): TStream;
begin
  Report( 'loading', aSource );
  Result := TFileStream.Create( aSource, fmOpenRead );
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TApplication
////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TApplication.Create( aOwner: TComponent );
begin
  inherited;
  StopOnException := True;
  ExceptionExitCode := 1;  // EXIT_FAILURE on most systems

  // Lazarus tries to modify this line on every change in project settings, so I placed it here.
  Title := 'GEX Editor';

  fExtension := TGmExtFileGEX.Create();
end;

destructor TApplication.Destroy();
begin
  fExtension.Destroy();

  inherited;
end;

procedure TApplication.DoRun();
begin
  WriteLn( Title, ' - Written by Dmitry D. Chernov, 2016-2020' );
  WriteLn(
    '; ' + {$I %DATE%} + ' ' + {$I %TIME%}
    + ' ; fpc ' + {$I %FPCVERSION%}
    + ' ; cpu ' + {$I %FPCTARGETCPU%}
    + ' ; sys ' + {$I %FPCTARGETOS%}
    + LineEnding
  );

  if ParamCount = 0 then begin
    ActionPrintUsage();
  end else begin
    case LowerCase( ExtractFileExt( Params[1] ) ) of
    '.ged', '.gmp':
      ActionCompose();
    '.gex':
      ActionDecompose();
    end;

    WriteLn( LineEnding, 'DONE OK' );
  end;

  // It's preferred to die from exceptions, so we don't bother about exitcodes.
  Terminate();
end;

////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TApplication.ActionPrintUsage();
begin
  WriteLn( 'Usage:' );
  WriteLn( '  exe <project.ged|package.gex> [output]' );
  WriteLn();
  WriteLn( 'exe project.ged' );
  WriteLn( '  - compose the GEX extension package using .ged / .gmp project' );
  WriteLn( '    (binary file formats of Extension Maker 1.2 / 1.01, respectively)' );
  WriteLn( 'exe package.gex' );
  WriteLn( '  - decompose an existing GEX extension package' );
  WriteLn();
  WriteLn( 'The optional ''output'' argument could be used to specify a custom filename' );
  WriteLn( '  of the package to be composed, or a folder name to store contents of a' );
  WriteLn( '  decomposed one.' );

  WriteLn();
end;

procedure TApplication.ActionCompose();
var
  ProjectFileName, PackageFileName : String;
  ProjectFile : TFileStream;
  PackageFile : TFileStream;
begin
  ProjectFileName := Params[1];

  PackageFileName := Params[2];
  if PackageFileName = '' then
    PackageFileName := ExtractFileNameWithoutExt( ProjectFileName );
  PackageFileName := MakeSafeFileName( PackageFileName+'.gex' );

  ProjectFile := nil;
  PackageFile := nil;

  try
    Report( 'reading', ProjectFileName );
    ProjectFile := TFileStream.Create( ProjectFileName, fmOpenRead );
    fExtension.Package.Prototype.LoadFromStream( ProjectFile );

    Report( 'composing', PackageFileName );
    PackageFile := TFileStream.Create( PackageFileName, fmCreate );
    fExtension.SaveToStream( PackageFile, @CB_PrepareReadingStreams, True, clMax );

  finally
    ProjectFile.Free();
    PackageFile.Free();

  end;
end;

procedure TApplication.ActionDecompose();
var
  PackageFileName, ProjectFileName, OutputFolder : String;
  PackageFile : TFileStream;
  ProjectFile : TFileStream;
begin
  PackageFileName := Params[1];

  OutputFolder := Params[2];
  if OutputFolder = '' then
    OutputFolder := ExtractFileNameWithoutExt( PackageFileName );

  ProjectFileName := MakeSafeFileName( OutputFolder+'.ged' );
  OutputFolder := MakeSafeFolderName( OutputFolder );

  PackageFile := nil;
  ProjectFile := nil;

  try
    Report( 'preparing', './'+OutputFolder+'/' );
    PackageFile := TFileStream.Create( PackageFileName, fmOpenRead );
    CreateDir( OutputFolder );
    SetCurrentDir( OutputFolder );

    Report( 'decomposing', PackageFileName );
    fExtension.LoadFromStream( PackageFile, @CB_PrepareWritingStreams );

    Report( 'writing', ProjectFileName );
    ProjectFile := TFileStream.Create( ProjectFileName, fmCreate );
    fExtension.Package.Prototype.Editable := True;
    fExtension.Package.Prototype.SaveToStream( ProjectFile, False );

  finally
    PackageFile.Free();
    ProjectFile.Free();

  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

var
  Application : TApplication;

{$R *.res}

begin
  Application := TApplication.Create(nil);
  Application.Run();
  Application.Free();
end.

