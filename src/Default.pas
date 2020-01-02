unit Default;

interface

type
 PInt8 = ^Int8;
 PInt16 = ^Int16;
 PInt32 = ^Int32;
 PInt64 = ^Int64;

 PUInt8 = ^UInt8;
 PUInt16 = ^UInt16;
 PUInt32 = ^UInt32;
 PUInt64 = ^UInt64;

 LChar = System.AnsiChar;
 WChar = System.WideChar;

 PLChar = System.PAnsiChar;
 PWChar = System.PWideChar;

 PInt64Rec = ^TInt64Rec;
 TInt64Rec = packed record
  case Boolean of
   False: (Lo, Hi: Int32);
   True: (Low, High: Int32);
 end;

 PUInt64Rec = ^TUInt64Rec;
 TUInt64Rec = packed record
  case Boolean of
   False: (Lo, Hi: UInt32);
   True: (Low, High: UInt32);
 end;

 LStr = System.AnsiString;
 WStr = System.WideString;
 UStr = System.UnicodeString;

 Boolean = System.Boolean;
 PBoolean = ^Boolean;

 Bool8 = System.ByteBool;
 Bool16 = System.WordBool;
 Bool32 = System.LongBool;

 NativeInt = {$IFDEF CPU64} Int64 {$ELSE} Int32 {$ENDIF};
 NativeUInt = {$IFDEF CPU64} UInt64 {$ELSE} UInt32 {$ENDIF};
 
 Int = NativeInt;
 UInt = NativeUInt;
 PInt = ^Int;
 PUInt = ^UInt;

 BoolArray = packed array[0..0] of Boolean;
 PBoolArray = ^BoolArray;

 ByteArray = packed array[0..0] of Byte;
 PByteArray = ^ByteArray;

 Int8Array = packed array[0..0] of Int8;
 UInt8Array = packed array[0..0] of UInt8;
 PInt8Array = ^Int8Array;
 PUInt8Array = ^UInt8Array;

 Int16Array = packed array[0..0] of Int16;
 UInt16Array = packed array[0..0] of UInt16;
 PInt16Array = ^Int16Array;
 PUInt16Array = ^UInt16Array;

 Int32Array = packed array[0..0] of Int32;
 UInt32Array = packed array[0..0] of UInt32;
 PInt32Array = ^Int32Array;
 PUInt32Array = ^UInt32Array;

 Int64Array = packed array[0..0] of Int64;
 UInt64Array = packed array[0..0] of UInt64;
 PInt64Array = ^Int64Array;
 PUInt64Array = ^UInt64Array;

 IntArray = packed array[0..0] of Int;
 UIntArray = packed array[0..0] of UInt;
 PIntArray = ^IntArray;
 PUIntArray = ^UIntArray;

 SingleArray = packed array[0..0] of Single;
 PSingleArray = ^SingleArray;

 PtrArray = packed array[0..0] of Pointer;

 LCharArray = packed array[0..0] of LChar;
 PLCharArray = packed array[0..0] of PLChar;
 WCharArray = packed array[0..0] of WChar;
 PWCharArray = packed array[0..0] of PWChar;


 Int8DynArray = array of Int8;
 UInt8DynArray = array of UInt8;

 Int16DynArray = array of Int16;
 UInt16DynArray = array of UInt16;

 Int32DynArray = array of Int32;
 UInt32DynArray = array of UInt32;

 Int64DynArray = array of Int64;
 UInt64DynArray = array of UInt64;

 NativeIntDynArray = array of NativeInt;
 NativeUIntDynArray = array of NativeUInt;

 PtrDynArray = array of Pointer;
 
 LCharDynArray = array of LChar;
 PLCharDynArray = array of PLChar;
 WCharDynArray = array of WChar;
 PWCharDynArray = array of PWChar;

 LCharSet = set of LChar;

const


 MinInt16 = Low(Int16);
 MaxInt16 = High(Int16);
 MinUInt16 = Low(UInt16);
 MaxUInt16 = High(UInt16);

 MinInt32 = Low(Int32);
 MaxInt32 = High(Int32);
 MinUInt32 = Low(UInt32);
 MaxUInt32 = High(UInt32);

 MinInt64 = Low(Int64);
 MaxInt64 = High(Int64);
 MinUInt64 = Low(UInt64);
 MaxUInt64 = High(UInt64);

 MinInt = MinInt32;
 MaxInt = MaxInt32;
 MinUInt = MinUInt32;
 MaxUInt = MaxUInt32;

 MinNativeInt = Low(NativeInt);
 MaxNativeInt = High(NativeInt);
 MinNativeUInt = Low(NativeUInt);
 MaxNativeUInt = High(NativeUInt);

 EmptyString: PLChar = '';
 LineBreak = {$IFDEF MSWINDOWS}#$D#$A{$ELSE}#$A{$ENDIF};

 PathSeparator = {$IFDEF MSWINDOWS}'\'{$ELSE}'/'{$ENDIF};
 PathSeparator2 = {$IFDEF MSWINDOWS}'/'{$ELSE}'\'{$ENDIF};
 DriveSeparator = ':' + PathSeparator;
 DriveSeparator2 = ':' + PathSeparator2;

 HexLookupTable: packed array[0..15] of LChar = '0123456789ABCDEF';

function Swap16(Value: Int16): Int16;
function Swap32(Value: Int32): Int32;
function Swap64(Value: Int64): Int64;

function Min32(X1, X2: Int32): Int32;
function Max32(X1, X2: Int32): Int32;
function Min64(X1, X2: Int64): Int64;
function Max64(X1, X2: Int64): Int64;
function Min(X1, X2: UInt): UInt;
function Max(X1, X2: UInt): UInt;

procedure StringFromVarRec(const Data: array of const; var S: LStr); overload;
function StringFromVarRec(const Data: array of const): LStr; overload;

procedure Alert(Msg: PLChar); overload;
procedure Alert(const Msg: array of const); overload;

function CopyStr(const S: LStr; StartPos, EndPos: UInt): LStr;
function CharPos(C: LChar; const S: LStr): UInt; overload;
function CharPos(C: LChar; S: PLChar): UInt; overload;
function CharPosEx(C: LChar; const S: LStr; Offset: UInt = 1): UInt; overload;
function CharPosEx(C: LChar; S: PLChar; Offset: UInt = 1): UInt; overload;

function IntPower(X: Double; Exp: UInt32): Double;

function StrLen(S: PLChar): UInt;
function StrCopy(Dest, Source: PLChar): PLChar;

function StrComp(S1, S2: PLChar): Int;
function StrIComp(S1, S2: PLChar): Int;
function StrLComp(S1, S2: PLChar; L: UInt): Int;
function StrLIComp(S1, S2: PLChar; L: UInt): Int;
function StrLScan(S: PLChar; C: LChar; MaxLen: UInt): PLChar;

function ExpandIntStr(const S: LStr; MinLength, MaxLength: UInt): LStr;

function IsPowerOf2(Value: UInt32): Boolean;
function NextPowerOf2(Value: UInt32): UInt32;

function LowerC(C: LChar): LChar; overload;
function UpperC(C: LChar): LChar; overload;

procedure StrTrim(var S: PLChar); overload;

procedure LowerCase(S: PLChar); overload;
procedure UpperCase(S: PLChar); overload;

procedure AppendSlash(S: PLChar);
procedure CorrectPath(S: PLChar; AppendSlash: Boolean = True);

function RoundTo(const X: Double; Digit: Int): Double;

function ArcSin(const X: Double): Double;
function ArcCos(const X: Double): Double;
function ArcTan2(const Y, X: Double): Double;

function HexToByte(S: PLChar): Byte;

function IntToStr(X: Int; out Buf; L: UInt): PLChar; overload;
function IntToStrE(X: Int; out Buf; L: UInt): PLChar;

function UIntToStr(X: UInt; out Buf; L: UInt): PLChar;
function UIntToStrE(X: UInt; out Buf; L: UInt): PLChar;

procedure ByteToHex(B: Byte; S: PLChar);

function Log10(const X: Double): Double;

function Ceil(const X: Double): Int;
function Floor(const X: Double): Int;

function StrToIntDef(S: PLChar; Def: Int): Int;
function StrToInt(S: PLChar): Int;

procedure MemSet(out Dest; Size: UInt; Value: Byte);
function StrLCopy(Dest, Source: PLChar; MaxLen: UInt): PLChar;
function StrLECopy(Dest, Source: PLChar; MaxLen: UInt): PLChar;
function StrECopy(Dest, Source: PLChar): PLChar;

function ExpandString(Src, Dst: PLChar; Size: UInt; MinSize: UInt): PLChar;

function VarArgsToString(S: PLChar; SP: Pointer; out Buf; BufSize: UInt): PLChar;

implementation

uses SysUtils {$IFDEF MSWINDOWS}, Windows{$ENDIF};

function Swap16(Value: Int16): Int16;
begin
  Result := (Value shl 8) or (Value shr 8);
end;

function Swap32(Value: Int32): Int32;
begin
  Result := (Value shl 24) or (Value shr 24) or ((Value shl 8) and $FF0000) or
          ((Value shr 8) and $FF00);
end;

function Swap64(Value: Int64): Int64;
begin
  Result := Swap32(TInt64Rec(Value).High) + (Int64(Swap32(TInt64Rec(Value).Low)) shl 32);
end;

function Min32(X1, X2: Int32): Int32;
begin
if X1 < X2 then
 Result := X1
else
 Result := X2;
end;

function Max32(X1, X2: Int32): Int32;
 begin
  if X1 > X2 then
   Result := X1
  else
   Result := X2;
 end;

function Min64(X1, X2: Int64): Int64;
begin
if X1 > X2 then
 Result := X2
else
 Result := X1;
end;

function Max64(X1, X2: Int64): Int64;
begin
if X1 < X2 then
 Result := X2
else
 Result := X1;
end;

function Min(X1, X2: UInt): UInt;
begin
if X1 > X2 then
 Result := X2
else
 Result := X1;
end;

function Max(X1, X2: UInt): UInt;
begin
if X1 < X2 then
 Result := X2
else
 Result := X1;
end;

procedure StringFromVarRec(const Data: array of const; var S: LStr);
const
 LookupTable: array[Boolean] of LStr = ('False', 'True');
var
 I: Int;
 Buf: array[1..128] of LChar;
begin
S := '';
for I := Low(Data) to High(Data) do
begin
 with Data[I] do
  case VType of
   vtInteger: S := S + IntToStr(VInteger, Buf, SizeOf(Buf));
   vtBoolean: S := S + LookupTable[VBoolean];
   vtChar: S := S + VChar;
   vtExtended: S := S + LStr(SysUtils.FloatToStr(VExtended^));
   vtString: S := S + VString^;
   vtPointer: S := S + IntToHex(NativeUInt(VPointer));
   vtPChar: S := S + VPChar;
   vtWideChar: S := S + LChar(VWideChar);
   vtPWideChar: S := S + PLChar(LStr(VPWideChar));
   vtAnsiString: S := S + LStr(VAnsiString);
   vtInt64: S := S + IntToStr(VInt64^);
   vtUnicodeString: S := S + LStr(UStr(VUnicodeString));
  else
   S := S + ' <unknown or unsupported type> ';
  end;
end;
end;

function StringFromVarRec(const Data: array of const): LStr;
begin
UInt(Result) := 0;
StringFromVarRec(Data, Result);
end;

procedure Alert(Msg: PLChar);
begin
{$IFDEF MSWINDOWS}
 MessageBoxA(0, Msg, 'Alert', MB_OK or MB_ICONWARNING or MB_SYSTEMMODAL);
{$ELSE}
 WriteLn(ErrOutput, Msg);
{$ENDIF}
end;

procedure Alert(const Msg: array of const);
begin
Alert(PLChar(StringFromVarRec(Msg)));
end;

function CopyStr(const S: LStr; StartPos, EndPos: UInt): LStr;
begin
if EndPos < StartPos then
 Result := ''
else
 Result := Copy(S, StartPos, EndPos - StartPos + 1);
end;

function CharPos(C: LChar; const S: LStr): UInt;
begin
Result := CharPosEx(C, S, 1);
end;

function CharPos(C: LChar; S: PLChar): UInt;
begin
Result := CharPosEx(C, S, 1);
end;

function CharPosEx(C: LChar; const S: LStr; Offset: UInt = 1): UInt;
var
 I: UInt;
begin
if S <> '' then
 for I := Offset to Length(S) do
  if S[I] = C then
   begin
    Result := I;
    Exit;
   end;

Result := 0;
end;

function CharPosEx(C: LChar; S: PLChar; Offset: UInt = 1): UInt;
var
 S2: PLChar;
begin
S2 := S;
S := PLChar(UInt(S) + Offset - 1);
while S^ > #0 do
 if S^ = C then
  begin
   Result := UInt(S) - UInt(S2) + 1;
   Exit;
  end
 else
  Inc(UInt(S));

Result := 0;
end;

function IntPower(X: Double; Exp: UInt32): Double;
 var
  I: UInt32;
 begin
  Result := X;
  if Exp > 0 then
   for I := 2 to Exp do
    Result := Result * X
  else
   Result := 1;
 end;

function StrLen(S: PLChar): UInt;

begin
Result := SysUtils.StrLen(S);
end;

function StrCopy(Dest, Source: PLChar): PLChar;
begin
  Result := SysUtils.StrCopy(Dest, Source);
end;

function StrComp(S1, S2: PLChar): Int;
begin
  Result := SysUtils.StrComp(S1, S2);
end;

function StrIComp(S1, S2: PLChar): Int;
begin
  Result := SysUtils.StrIComp(S1, S2);
end;

function StrLComp(S1, S2: PLChar; L: UInt): Int;
begin
  Result := SysUtils.StrLComp(S1, S2, L);
end;

function StrLIComp(S1, S2: PLChar; L: UInt): Int;
begin
  Result := SysUtils.StrLIComp(S1, S2, L);
end;

function StrLScan(S: PLChar; C: LChar; MaxLen: UInt): PLChar;
begin
while (S^ > #0) and (MaxLen > 0) do
 if S^ = C then
  begin
   Result := S;
   Exit;
  end
 else
  begin
   Inc(UInt(S));
   Dec(MaxLen);
  end;

if (MaxLen > 0) and (C = #0) then
 Result := S
else
 Result := nil;
end;

procedure StrTrim(var S: PLChar);
begin
while S^ = ' ' do
 Inc(UInt(S));
end;

function ExpandIntStr(const S: LStr; MinLength, MaxLength: UInt): LStr;
var
 L: UInt;
begin
if (MaxLength > 0) and (MinLength > MaxLength) then
 Result := ''
else
 begin
  L := Length(S);
  if L >= MinLength then
   if (L > MaxLength) and (MaxLength > 0) then
    Result := Copy(S, L - MaxLength + 1, MaxLength)
   else
    Result := S
  else
   begin
    SetLength(Result, MinLength);
    UniqueString(Result);
    MemSet(Pointer(Result)^, MinLength - L, Ord('0'));
    Move(Pointer(S)^, Pointer(UInt(Result) + MinLength - L)^, L);
   end;
 end;
end;

function IsPowerOf2(Value: UInt32): Boolean;
begin
Result := (Value > 0) and (Value and (Value - 1) = 0);
end;

function NextPowerOf2(Value: UInt32): UInt32;
begin
if Value = 0 then
 Result := 0
else
 begin
  Dec(Value);
  Value := Value or (Value shr 1);
  Value := Value or (Value shr 2);
  Value := Value or (Value shr 4);
  Value := Value or (Value shr 8);
  Value := Value or (Value shr 16);
  Result := Value + 1;
 end;
end;

function LowerC(C: LChar): LChar;
 begin
  if C in ['A'..'Z'] then
   Result := LChar(Ord(C) or $20)
  else
   Result := C;
 end;

function UpperC(C: LChar): LChar;
 begin
  if C in ['a'..'z'] then
   Result := LChar(Ord(C) and $DF)
  else
   Result := C;
 end;

procedure LowerCase(S: PLChar);
begin
if S <> nil then
 while S^ > #0 do
  begin
   if S^ in ['A'..'Z'] then
    S^ := LChar(Ord(S^) or $20);
   Inc(UInt(S));
  end;
end;

procedure UpperCase(S: PLChar);
begin
if S <> nil then
 while S^ > #0 do
  begin
   if S^ in ['a'..'z'] then
    S^ := LChar(Ord(S^) and $DF);
   Inc(UInt(S));
  end;
end;

procedure AppendSlash(S: PLChar);
begin
if S <> nil then
 begin
  S := PLChar(UInt(S) + StrLen(S) - SizeOf(S^));
  if not (S^ in [PathSeparator, PathSeparator2]) then
   PUInt16(UInt(S) + SizeOf(S^))^ := Byte(PathSeparator);
 end;
end;

procedure CorrectPath(S: PLChar; AppendSlash: Boolean = True);
begin
if (S <> nil) and (S^ > #0) then
 while True do
  begin
   case S^ of
    #0:
     begin
      if AppendSlash and (PLChar(UInt(S) - SizeOf(S^))^ <> PathSeparator) then
       PUInt16(S)^ := Byte(PathSeparator);
      Break;
     end;

    'A'..'Z': S^ := LChar(Ord(S^) or $20);
    PathSeparator2: S^ := PathSeparator;
   end;
   Inc(UInt(S));
  end;
end;

function RoundTo(const X: Double; Digit: Int): Double;
type
 T = array[1..2] of Double;
var
 P: ^T;
 CW: UInt16;
const
 Factors : array[-20..20] of T =
  ((1E-20, 1E20), (1E-19, 1E19), (1E-18, 1E18), (1E-17, 1E17), (1E-16, 1E16),
   (1E-15, 1E15), (1E-14, 1E14), (1E-13, 1E13), (1E-12, 1E12), (1E-11, 1E11),
   (1E-10, 1E10), (1E-09, 1E09), (1E-08, 1E08), (1E-07, 1E07), (1E-06, 1E06),
   (1E-05, 1E05), (1E-04, 1E04), (1E-03, 1E03), (1E-02, 1E02), (1E-01, 1E01),
   (1, 1),
   (1E01, 1E-01), (1E02, 1E-02), (1E03, 1E-03), (1E04, 1E-04), (1E05, 1E-05),
   (1E06, 1E-06), (1E07, 1E-07), (1E08, 1E-08), (1E09, 1E-09), (1E10, 1E-10),
   (1E11, 1E-11), (1E12, 1E-12), (1E13, 1E-13), (1E14, 1E-14), (1E15, 1E-15),
   (1E16, 1E-16), (1E17, 1E-17), (1E18, 1E-18), (1E19, 1E-19), (1E20, 1E-20));
begin
if Abs(Digit) > 20 then
 Result := X
else
 begin
  CW := Get8087CW;
  Set8087CW(4978);
  if Digit = 0 then
   Result := Round(X)
  else
   begin
    P := @Factors[Digit];
    Result := Round(X * P[2]) * P[1];
   end;
  Set8087CW(CW);
 end;
end;

function ArcTan2(const Y, X: Double): Double;
var
 I: Double;
begin
I := 32 * X * X + 9 * Y * Y;
if I = 0 then
 if X > 0 then
  Result := 90
 else
  Result := 270
else
 begin
  I := 32 * (X * Y) / I;
  if X >= 0 then
   if Y >= 0 then
    Result := I
   else
    Result := 360 - I
  else
   if Y >= 0 then
    Result := 90 + I
   else
    Result := 270 - I;
 end;
end;

function ArcCos(const X: Double): Double;
begin
Result := ArcTan2(Sqrt(1 - X * X), X);
end;

function ArcSin(const X: Double): Double;
begin
Result := ArcTan2(X, Sqrt(1 - X * X));
end;

function HexToByte(S: PLChar): Byte;
var
 C: LChar;
 B: Byte;
 I: UInt;
begin
Result := 0;
for I := 1 to 2 do
 begin
  C := S^;
  if (C >= '0') and (C <= '9') then
   B := Ord(C) - Ord('0')
  else
   if (C >= 'A') and (C <= 'F') then
    B := Ord(C) - Ord('A') + $A
   else
    if (C >= 'a') and (C <= 'f') then
     B := Ord(C) - Ord('a') + $A
    else
     if C = #0 then
      Break
     else
      begin
       Result := 0;
       Exit;
      end;

  Inc(UInt(S));
  Result := Result shl 4 + B;
 end;
end;

function Log10(const X: Double): Double;
begin
  Result := Ln(X) / Ln(10);
end;

function IntToStr(X: Int; out Buf; L: UInt): PLChar;
var
 B: Boolean;
 N: UInt;
 S: PLChar;
begin
B := X < 0;
if X = Low(X) then
 X := 0
else
 X := Abs(X);
N := Trunc(Log10(X + Int(X = 0))) + 1 + UInt(B);

if L <= N then
 begin
  PLChar(@Buf)^ := #0;
  Result := nil;
 end
else
 begin
  S := @Buf;

  if B then
   S^ := '-';

  S := PLChar(UInt(S) + N);
  S^ := #0;
  Dec(UInt(S));
  
  repeat
   S^ := LChar(Ord('0') + (X mod 10));
   Dec(UInt(S));
   X := X div 10;
  until (X = 0);

  Result := @Buf;
 end;
end;

function UIntToStr(X: UInt; out Buf; L: UInt): PLChar;
var
 N: UInt;
 S: PLChar;
begin
N := Trunc(Log10(X + UInt(X = 0))) + 1;

if L <= N then
 begin
  PLChar(@Buf)^ := #0;
  Result := nil;
 end
else
 begin
  S := PLChar(UInt(@Buf) + N);
  S^ := #0;
  Dec(UInt(S));

  repeat
   S^ := LChar(Ord('0') + (X mod 10));
   Dec(UInt(S));
   X := X div 10;
  until (X = 0);

  Result := @Buf;
 end;
end;

function IntToStrE(X: Int; out Buf; L: UInt): PLChar;
var
 B: Boolean;
 N: UInt;
 S: PLChar;
begin
B := X < 0;
if X = Low(X) then
 X := 0
else
 X := Abs(X);
N := Trunc(Log10(X + Int(X = 0))) + 1 + UInt(B);

if L <= N then
 begin
  PLChar(@Buf)^ := #0;
  Result := nil;
 end
else
 begin
  S := @Buf;

  if B then
   S^ := '-';

  S := PLChar(UInt(S) + N);
  Result := S;  
  S^ := #0;
  Dec(UInt(S));

  repeat
   S^ := LChar(Ord('0') + (X mod 10));
   Dec(UInt(S));
   X := X div 10;
  until (X = 0);
 end;
end;

function UIntToStrE(X: UInt; out Buf; L: UInt): PLChar;
var
 N: UInt;
 S: PLChar;
begin
N := Trunc(Log10(X + UInt(X = 0))) + 1;

if L <= N then
 begin
  PLChar(@Buf)^ := #0;
  Result := nil;
 end
else
 begin
  S := PLChar(UInt(@Buf) + N);
  Result := S;  
  S^ := #0;
  Dec(UInt(S));

  repeat
   S^ := LChar(Ord('0') + (X mod 10));
   Dec(UInt(S));
   X := X div 10;
  until (X = 0);
 end;
end;

procedure ByteToHex(B: Byte; S: PLChar);
begin
PUInt16(S)^ := Byte(HexLookupTable[B shr 4]) + (Byte(HexLookupTable[B and $F]) shl 8);
PLChar(UInt(S) + SizeOf(UInt16))^ := #0;
end;

procedure MemSet(out Dest; Size: UInt; Value: Byte);
begin
  FillChar(Dest, Size, Value);
end;


// Experimental
function StrLCopy(Dest, Source: PLChar; MaxLen: UInt): PLChar;
begin
Result := Dest;
while (Source^ > #0) and (MaxLen > 0) do
 begin
  Dest^ := Source^;
  Inc(UInt(Dest));
  Inc(UInt(Source));
  Dec(MaxLen);
 end;
Dest^ := #0;
end;

function StrLECopy(Dest, Source: PLChar; MaxLen: UInt): PLChar;
begin
while (Source^ > #0) and (MaxLen > 0) do
 begin
  Dest^ := Source^;
  Inc(UInt(Dest));
  Inc(UInt(Source));
  Dec(MaxLen);
 end;
Dest^ := #0;
Result := Dest;
end;

function StrECopy(Dest, Source: PLChar): PLChar;
begin
while Source^ > #0 do
 begin
  Dest^ := Source^;
  Inc(UInt(Dest));
  Inc(UInt(Source));
 end;
Dest^ := #0;
Result := Dest;
end;

function StrEnd(S: PLChar): PLChar;
begin
Result := PLChar(UInt(S) + StrLen(S));
end;

function Ceil(const X: Double): Int;
begin
Result := Trunc(X);
if Frac(X) > 0 then
 Inc(Result);
end;

function Floor(const X: Double): Int;
begin
Result := Trunc(X);
if Frac(X) < 0 then
 Dec(Result);
end;

function StrToIntDef(S: PLChar; Def: Int): Int;
var
 B: Boolean;
 C: LChar;
begin
B := S^ = '-';
if B or (S^ = '+') then
 Inc(UInt(S));

Result := 0;
repeat
 C := S^;
 if C = #0 then
  Break
 else
  if (C < '0') or (C > '9') then
   begin
    Result := Def;
    Exit;
   end
  else
   begin
    Result := Result * 10 + (Ord(C) - Ord('0'));
    Inc(UInt(S));
   end;
until False;

if B then
 Result := -Result;
end;

function StrToInt(S: PLChar): Int;
begin
Result := StrToIntDef(S, 0);
end;

function ExpandString(Src, Dst: PLChar; Size: UInt; MinSize: UInt): PLChar;
var
 L: UInt;
begin
Result := Dst;

if Size > 0 then
 if MinSize >= Size then
  Dst^ := #0
 else
  begin
   L := StrLen(Src);
   if L < MinSize then
    begin
     MemSet(Dst^, MinSize - L, Ord('0'));
     Inc(UInt(Dst), MinSize - L);
     Dec(Size, MinSize - L);
    end;

   StrLCopy(Dst, Src, Min(Size, L + 1) - 1);
  end;
end;

function StrToFloatDef(S: PLChar; Def: Double): Double;
var
 B: Boolean;
 C: LChar;
 FP: PLChar;
begin
B := S^ = '-';
if B or (S^ = '+') then
 Inc(UInt(S));

Result := 0;
FP := nil;
repeat
 C := S^;
 if C = #0 then
  Break
 else
  if C = '.' then
   if FP = nil then
    FP := PLChar(UInt(S) + 1)
   else
    begin
     Result := Def;
     Exit;
    end
  else
   if (C < '0') or (C > '9') then
    begin
     Result := Def;
     Exit;
    end
   else
    Result := Result * 10 + (Ord(C) - Ord('0'));

 Inc(UInt(S));
until False;

if FP <> nil then
 while UInt(S) > UInt(FP) do
  begin
   Result := Result / 10;
   Dec(UInt(S));
  end;

if B then
 Result := -Result;
end;

function VarArgsToString(S: PLChar; SP: Pointer; out Buf; BufSize: UInt): PLChar;
var
 S2, Dst: PLChar;
 RemBuf: UInt;
 TmpBuf: array[1..4] of LChar;

 function Extract: Pointer;
 begin
  Result := SP;
  Inc(UInt(SP), SizeOf(UInt));
 end;

 procedure Append(S: PLChar; OptLen: Int = -1);
 begin
  if (RemBuf > 1) and (OptLen <> 0) then
   begin
    if OptLen <> -1 then
     S := StrLECopy(Dst, S, Min(RemBuf - 1, OptLen))
    else
     S := StrLECopy(Dst, S, RemBuf - 1);
    Dec(RemBuf, UInt(S) - UInt(Dst));
    Dst := S;
   end;
 end;

begin
if (S = nil) or (BufSize = 0) then
 Result := nil
else
 begin
  Inc(UInt(SP), SizeOf(UInt));
  Dst := @Buf;
  RemBuf := BufSize;
  TmpBuf[2] := #0;

  S2 := StrScan(S, '%');
  while S2 <> nil do
   begin
    Append(S, UInt(S2) - UInt(S));

    Inc(UInt(S2));
    case S2^ of
     #0: Break;
     'd', 'i': Append(IntToStr(PInt32(Extract)^, Dst^, RemBuf));
     'u': Append(UIntToStr(PUInt32(Extract)^, Dst^, RemBuf));
     'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A': Append(PLChar(FloatToStr(PSingle(Extract)^)));
     'x', 'X': Append(PLChar(IntToHex(PUInt32(Extract)^)));
     'c':
      begin
       TmpBuf[1] := PLChar(Extract)^;
       Append(@TmpBuf);
      end;
     '%':
      begin
       TmpBuf[1] := '%';
       Append(@TmpBuf);
      end;
     's':
      begin
       S := PLChar(Extract);
       if S <> nil then
        begin
         S := PLChar(Pointer(S)^);
         Append(S);
        end;
      end;
    end;

    S := PLChar(UInt(S2) + 1);
    S2 := StrScan(S, '%');
   end;

  Append(S);
  Result := @Buf;
 end;
end;

end.
