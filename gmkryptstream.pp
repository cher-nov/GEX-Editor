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

  TGmKryptCipherTable = array[Byte] of Byte;
  TGmKryptStreamClass = class of TCustomGmKryptStream;

  TCustomGmKryptStream = class( TOwnerStream )
  strict protected
    fCipherTable : TGmKryptCipherTable;
    fKeySeed : LongInt;
    fAdditiveCrypto : Boolean;
    fByteCounter : Int64;
  protected
    function GetPosition(): Int64; override;
    function GetSize(): Int64; override;
  public
    procedure AfterConstruction(); override;
    function InitState( aKeySeed: LongInt; aAdditiveCrypto: Boolean ): Boolean; virtual;
    function IsIdenticalCrypto(): Boolean; inline;
    function Seek( const Offset: Int64; Origin: TSeekOrigin ): Int64; override;
    property KeySeed: LongInt read fKeySeed;
    property AdditiveCipher: Boolean read fAdditiveCrypto;
    property ByteCounter: Int64 read fByteCounter;
  end;

  TGmKryptEncodeStream = class( TCustomGmKryptStream )
  public
    function Write( const Buffer; Count: LongInt ): LongInt; override;
  end;

  TGmKryptDecodeStream = class( TCustomGmKryptStream )
  public
    function InitState( aKeySeed: LongInt; aAdditiveCrypto: Boolean ): Boolean; override;
    function Read( var Buffer; Count: LongInt ): LongInt; override;
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
  fKeySeed := cGmKryptIdentityKeySeed;
end;

function TCustomGmKryptStream.InitState( aKeySeed: LongInt; aAdditiveCrypto: Boolean ): Boolean;
var
  a, b : Integer;
  swap : Byte;
  i, j : Integer;
begin
  fByteCounter := 0;  // note: the first byte is always unencrypted

  fKeySeed := aKeySeed;
  fAdditiveCrypto := aAdditiveCrypto;

  Result := IsIdenticalCrypto();
  if Result then exit;

  for i in Byte do
    fCipherTable[i] := i;

  a := (aKeySeed mod 250) + 6;
  b := aKeySeed div 250;

  for i := 1 to 10000 do begin
    j := ( (i*a+b) mod 254 ) + 1;
    swap := fCipherTable[j];
    fCipherTable[j] := fCipherTable[j+1];
    fCipherTable[j+1] := swap;
  end;
end;

function TCustomGmKryptStream.IsIdenticalCrypto(): Boolean;
begin
  Result := (fKeySeed - cGmKryptIdentityKeySeed) mod 250 = 0;  // check for identity keys
  Result := Result and not fAdditiveCrypto;  // check for non-identity method
end;

function TCustomGmKryptStream.Seek( const Offset: Int64; Origin: TSeekOrigin ): Int64;
var
  BasePosition, NewCounterValue : Int64;
begin
  Case Word(Origin) of
    soFromBeginning:
      BasePosition := fSource.Position;
    soFromEnd:
      BasePosition := fSource.Position - fSource.Size;
    else  // soFromCurrent:
      BasePosition := 0;
  end;

  NewCounterValue := fByteCounter - BasePosition + Offset;
  if not IsIdenticalCrypto() and fAdditiveCrypto and (NewCounterValue < 0)then
    InvalidSeek();

  Result := fSource.Seek( Offset, Origin );
  fByteCounter := NewCounterValue;
end;

// these overrides are provided to prevent Seek() invocation by default implementations
function TCustomGmKryptStream.GetPosition(): Int64;
begin
  Result := fSource.Position;
end;

function TCustomGmKryptStream.GetSize(): Int64;
begin
  Result := fSource.Size;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmKryptEncodeStream
////////////////////////////////////////////////////////////////////////////////////////////////////

function TGmKryptEncodeStream.Write( const Buffer; Count: LongInt ): LongInt;
var
  SourceData, OutputData : PByte;
  code : Byte;
  i : LongInt;
begin
  if IsIdenticalCrypto() then begin
    SourceData := nil;
    OutputData := @Buffer;
  end else begin
    SourceData := GetMemory( Count );
    Move( Buffer, SourceData^, Count );
    OutputData := SourceData;

    // skip first byte as required
    if fByteCounter = 0 then
      i := 1
    else
      i := 0;
  
    for i := i to Count-1 do begin
      code := SourceData[i];
      if fAdditiveCrypto then
        code := SizeInt(code + fByteCounter + i) and 255;
      SourceData[i] := fCipherTable[code];
    end;
  end;

  try
    Result := fSource.Write( OutputData^, Count );
    fByteCounter += Result;
  finally
    FreeMemory( SourceData );
  end;
end;

////////////////////////////////////////////////////////////////////////////////////////////////////
// TGmKryptDecodeStream
////////////////////////////////////////////////////////////////////////////////////////////////////

function TGmKryptDecodeStream.InitState( aKeySeed: LongInt; aAdditiveCrypto: Boolean ): Boolean;
var
  DecodeTable : TGmKryptCipherTable;
  i : Integer;
begin
  Result := inherited;
  if Result then exit;

  for i in Byte do
    DecodeTable[ fCipherTable[i] ] := i;
  fCipherTable := DecodeTable;
end;

function TGmKryptDecodeStream.Read( var Buffer; Count: LongInt ): LongInt;
var
  TargetData : PByte;
  code : Byte;
  i : LongInt;
begin
  Result := fSource.Read( Buffer, Count );
  fByteCounter += Result;
  if IsIdenticalCrypto() then exit;

  // skip first byte as required
  if fByteCounter = Result then
    i := 1
  else
    i := 0;

  TargetData := PByte(@Buffer);
  for i := i to Result-1 do begin
    code := fCipherTable[ TargetData[i] ];
    if fAdditiveCrypto then
      code := SizeInt(code - fByteCounter - i) and 255;
    TargetData[i] := code;
  end;
end;

end.

