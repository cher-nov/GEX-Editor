unit GmKryptStream;

{
  gmkryptstream.pas
  Custom TStream subclasses to deal with the GMKrypt encryption
  used by GameMaker.

  Written by Dmitry D. Chernov aka Black Doomer.
  Based on the original GMKrypt description and sources of the
  encoding and decoding algorithms by IsmAvatar and Quadduc.
}

{$MODE OBJFPC}
{$LONGSTRINGS ON}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
interface
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

uses
  SysUtils, Classes;

const
  // with this key, data essentially remains unencrypted in non-additive mode
  cGmKryptIdentityKeySeed = 248;

////////////////////////////////////////////////////////////////////////////////////////////////////
type

  TGmKryptSwapTable = array[Byte] of Byte;
  TGmKryptStreamClass = class of TCustomGmKryptStream;

  TCustomGmKryptStream = class( TOwnerStream )
  strict protected
    fEncodeTable : TGmKryptSwapTable;
    fDecodeTable : TGmKryptSwapTable;
    fBasePosition : Int64;
    fKeySeed : LongInt;
    fAdditiveCipher : Boolean;
  protected
    function GetPosition(): Int64; override;
    function GetSize(): Int64; override;
  public
    procedure AfterConstruction(); override;
    function SetState( aKeySeed: LongInt; aAdditiveCipher: Boolean ): Boolean; virtual;
    function IsIdenticalState(): Boolean; inline;
    function Seek( const Offset: Int64; Origin: TSeekOrigin ): Int64; override;
    function Read( var Buffer; Count: LongInt ): LongInt; override;
    function Write( const Buffer; Count: LongInt ): LongInt; override;
    property KeySeed: LongInt read fKeySeed;
    property AdditiveCipher: Boolean read fAdditiveCipher;
  end;

  TGmKryptStream = class( TCustomGmKryptStream )
    // This class is provided to use it for ownership and context sharing. If you want to
    // use crypto stream just as a regular data source, use TCustomGmKryptStream instead.
  end;

function GmKryptRandomKeySeed(): LongInt;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

function GmKryptRandomKeySeed(): LongInt;
begin
  Result := Random( LongInt(25600) ) + 3328;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TCustomGmKryptStream
////////////////////////////////////////////////////////////////////////////////////////////////////

procedure TCustomGmKryptStream.AfterConstruction();
begin
  SetState( cGmKryptIdentityKeySeed, False );
end;

function TCustomGmKryptStream.SetState( aKeySeed: LongInt; aAdditiveCipher: Boolean ): Boolean;
var
  a, b : Integer;
  swap : Byte;
  i, j : Integer;
begin
  fBasePosition := fSource.Position;  // note: the first byte is always unencrypted
  fKeySeed := aKeySeed;
  fAdditiveCipher := aAdditiveCipher;

  Result := IsIdenticalState();
  if Result then exit;

  for i in Byte do
    fEncodeTable[i] := i;

  a := (aKeySeed mod 250) + 6;
  b := aKeySeed div 250;

  for i := 1 to 10000 do begin
    j := ( (i*a+b) mod 254 ) + 1;
    swap := fEncodeTable[j];
    fEncodeTable[j] := fEncodeTable[j+1];
    fEncodeTable[j+1] := swap;
  end;

  for i in Byte do
    fDecodeTable[ fEncodeTable[i] ] := i;
end;

function TCustomGmKryptStream.IsIdenticalState(): Boolean;
begin
  Result := (fKeySeed - cGmKryptIdentityKeySeed) mod 250 = 0;  // check for identity keys
  Result := Result and not fAdditiveCipher;  // check for non-identity method
end;

function TCustomGmKryptStream.Seek( const Offset: Int64; Origin: TSeekOrigin ): Int64;
var
  BaseShift : Int64;
begin
  if not IsIdenticalState() then begin
    case Word(Origin) of
      soFromBeginning:
        BaseShift := 0;
      soFromEnd:
        BaseShift := GetSize() - 1;
      else  // soFromCurrent:
        BaseShift := GetPosition();
    end;

    if Offset < -BaseShift then
      InvalidSeek();
  end;

  Result := fSource.Seek( Offset, Origin );
end;

function TCustomGmKryptStream.Read( var Buffer; Count: LongInt ): LongInt;
var
  TargetData : PByte;
  code : Byte;
  i : LongInt;
begin
  Result := fSource.Read( Buffer, Count );
  if IsIdenticalState() then exit;

  // skip first byte as required
  if GetPosition() = Result then
    i := 1
  else
    i := 0;

  TargetData := PByte(@Buffer);
  for i := i to Result-1 do begin
    code := fDecodeTable[ TargetData[i] ];
    if fAdditiveCipher then
      code := SizeInt(code - GetPosition() - i) and 255;
    TargetData[i] := code;
  end;
end;

function TCustomGmKryptStream.Write( const Buffer; Count: LongInt ): LongInt;
var
  SourceData, OutputData : PByte;
  code : Byte;
  i : LongInt;
begin
  if IsIdenticalState() then begin
    SourceData := nil;
    OutputData := @Buffer;
  end else begin
    SourceData := GetMemory( Count );
    Move( Buffer, SourceData^, Count );
    OutputData := SourceData;

    // skip first byte as required
    if GetPosition() = 0 then
      i := 1
    else
      i := 0;
  
    for i := i to Count-1 do begin
      code := SourceData[i];
      if fAdditiveCipher then
        code := SizeInt(code + GetPosition() + i) and 255;
      SourceData[i] := fEncodeTable[code];
    end;
  end;

  try
    Result := fSource.Write( OutputData^, Count );
  finally
    FreeMemory( SourceData );
  end;
end;

function TCustomGmKryptStream.GetPosition(): Int64;
begin
  Result := fSource.Position - fBasePosition;
end;

function TCustomGmKryptStream.GetSize(): Int64;
begin
  Result := fSource.Size - fBasePosition;
end;

end.

