unit NetchanMain;

interface

uses
  SysUtils, Default, SDK;

type
 TFragmentSizeFunc = function(Client: Pointer): UInt32; cdecl;

type
  // Netchan
  PNetchan = ^TNetchan; // 9504 on hw.dll    9236 linux
  TNetchan = record
    Source: TNetSrc; // +0, fully confirmed: 0, 1, 2 are possible values
    Addr: TNetAdr; // +4, fully confirmed
    ClientIndex: UInt32; // +24, fully confirmed client index
    LastReceived, FirstReceived: Single; // +28 and +32

    Rate: Double; // +40 | +36, guess it's confirmed
    ClearTime: Double; // +48 | +44 fully confirmed

    IncomingSequence: Int32; // +56 confirmed fully (2nd step)
    IncomingAcknowledged: Int32; // +60 confirmed fully
    IncomingReliableAcknowledged: Int32; // +64 confirmed fully
    IncomingReliableSequence: Int32; // +68 confirmed fully (2nd step)

    OutgoingSequence: Int32; // W 72   L 68 confirmed fully (2nd step)
    ReliableSequence: Int32; // W 76 L 72  confirmed fully
    LastReliableSequence: Int32; // W 80 L 76 confirmed fully

    Client: Pointer; // +84 | +80, confirmed  pclient
    FragmentFunc: TFragmentSizeFunc; // +88 | +84, fully confirmed
    NetMessage: TSizeBuf; // +92 | +88, fully confirmed
    NetMessageBuf: array[1..MAX_NETCHANLEN] of Byte; // W 112,  L 108 fully confirmed

    ReliableLength: UInt32; // +4104 yeah confirmed
    ReliableBuf: array[1..MAX_NETCHANLEN] of Byte; // W 4108 confirmed   L 4104 confirmed

    // this fragbuf stuff seems to be confirmed
    FragBufQueue: array[TNetStream] of PFragBufDir; // W 8100   L 8096?
    FragBufActive: array[TNetStream] of Boolean; // W 8108
    FragBufSequence: array[TNetStream] of Int32; // W 8116
    FragBufBase: array[TNetStream] of PFragBuf; // W 8124   L ?8120
    FragBufNum: array[TNetStream] of UInt32; // W 8132 L 8128
    FragBufOffset: array[TNetStream] of UInt16; // W 8140
    FragBufSize: array[TNetStream] of UInt16; // W 8144

    IncomingBuf: array[TNetStream] of PFragBuf; // W 8148 L 8144
    IncomingReady: array[TNetStream] of Boolean; // W 8156 L 8152  is completed

    FileName: array[1..MAX_PATH_A] of LChar; // W 8164 confirmed

    TempBuffer: Pointer; // W 8424
    TempBufferSize: UInt32; // W 8428

    Flow: array[TFlowSrc] of TNetchanFlowData; // W 8432    flow data size = 536

  public
    procedure FragSend;
    procedure Clear;
    procedure CreateFragments(var SB: TSizeBuf);
    procedure CreateFileFragmentsFromBuffer(Name: PLChar; Buffer: Pointer; Size: UInt);
    function CreateFileFragments(Name: PLChar): Boolean;
    procedure FlushIncoming(Stream: TNetStream);
    procedure Setup(ASource: TNetSrc; const AAddr: TNetAdr; ClientID: Int; ClientPtr: Pointer; Func: TFragmentSizeFunc);
    function Process: Boolean;
    procedure Transmit(Size: UInt; Buffer: Pointer);
    function IsIncomingReady: Boolean;
    function CopyNormalFragments: Boolean;
    function CopyFileFragments: Boolean;
    function CanPacket: Boolean;
    procedure ClearFragments;
    procedure UpdateFlow;
  end;

type
  Netchan = class
  public
    class procedure OutOfBandPrint(Source: TNetSrc; const Addr: TNetAdr; S: PLChar); overload;
    class procedure OutOfBandPrint(Source: TNetSrc; const Addr: TNetAdr; const S: array of const); overload;

    class procedure AddBufferToList(var Base: PFragBuf; P: PFragBuf);
    class procedure Init;

  private
    class procedure UnlinkFragment(Frag: PFragBuf; var Base: PFragBuf);
    class procedure ClearFragBufs(var P: PFragBuf);
    class procedure PushStreams(var C: TNetchan; var SendReliable: Boolean);
    class function AllocFragBuf: PFragBuf;
    class function FindBufferByID(var Base: PFragBuf; Index: UInt; Alloc: Boolean): PFragBuf;
    class procedure CheckForCompletion(var C: TNetchan; Index: TNetStream; Total: UInt);
    class function ValidateHeader(Ready: Boolean; Seq, Offset, Size: UInt): Boolean;
    class procedure AddFragBufToTail(Dir: PFragBufDir; var Tail: PFragBuf; P: PFragBuf);
    class procedure AddDirToQueue(var Queue: PFragBufDir; Dir: PFragBufDir);
    class function CompressBuf(SrcBuf: Pointer; SrcSize: UInt; out DstBuf: Pointer; out DstSize: UInt): Boolean;
    class function GetFileInfo(var C: TNetchan; Name: PLChar; out Size, CompressedSize: UInt; out Compressed: Boolean): Boolean;
    class function DecompressIncoming(FileName: PLChar; var Src: Pointer; var TotalSize: UInt; IncomingSize: UInt): Boolean;
  end;

var
 net_showpackets: TCVar = (Name: 'net_showpackets'; Data: '0');

implementation

uses BZip2, Common, Console, FileSys, Memory, MsgBuf, HostMain, HostCmds,
  Resource, SVClient, SVMain, SysArgs, SysMain, Network, Client;

var
 // netchan stuff
 net_showdrop: TCVar = (Name: 'net_showdrop'; Data: '0');
 net_chokeloop: TCVar = (Name: 'net_chokeloop'; Data: '0');
 sv_filetransfercompression: TCVar = (Name: 'sv_filetransfercompression'; Data: '1');
 sv_filetransfermaxsize: TCVar = (Name: 'sv_filetransfermaxsize'; Data: '20000000');
 sv_filereceivemaxsize: TCVar = (Name: 'sv_filereceivemaxsize'; Data: '1000000');
 sv_receivedecalsonly: TCVar = (Name: 'sv_receivedecalsonly'; Data: '1');

 // 0 - disabled
 // 1 - normal packets only
 // 2 - files only
 // 3 - packets & files
 net_compress: TCVar = (Name: 'net_compress'; Data: '3');

class procedure Netchan.OutOfBandPrint(Source: TNetSrc; const Addr: TNetAdr; S: PLChar);
  procedure Netchan_OutOfBand(Source: TNetSrc; const Addr: TNetAdr; Size: UInt; Data: Pointer);
  var
   SB: TSizeBuf;
   Buf: array[1..MAX_PACKETLEN] of Byte;
  begin
  SB.Name := 'Netchan_OutOfBand';
  SB.AllowOverflow := [FSB_ALLOWOVERFLOW];
  SB.Data := @Buf;
  SB.MaxSize := SizeOf(Buf);
  SB.CurrentSize := 0;

  MSG_WriteLong(SB, OUTOFBAND_TAG);
  SZ_Write(SB, Data, Size);
  if not (FSB_OVERFLOWED in SB.AllowOverflow) then
   NET_SendPacket(Source, SB.CurrentSize, SB.Data, Addr);
  end;
begin
Netchan_OutOfBand(Source, Addr, StrLen(S) + 1, S);
end;

class procedure Netchan.OutOfBandPrint(Source: TNetSrc; const Addr: TNetAdr; const S: array of const);
begin
Netchan.OutOfBandPrint(Source, Addr, PLChar(StringFromVarRec(S)));
end;

class procedure Netchan.UnlinkFragment(Frag: PFragBuf; var Base: PFragBuf);
var
 P: PFragBuf;
begin
if Base = nil then
 DPrint('Netchan_UnlinkFragment: Asked to unlink fragment from empty list, ignored.')
else
 if Frag = Base then
  begin
   Base := Frag.Next;
   Mem_Free(Frag);
  end
 else
  begin
   P := Base;
   while P.Next <> nil do
    if P.Next = Frag then
     begin
      P.Next := Frag.Next;
      Mem_Free(Frag);
      Exit;
     end
    else
     P := P.Next;

   DPrint('Netchan_UnlinkFragment: Couldn''t find fragment.');
  end;
end;

class procedure Netchan.ClearFragBufs(var P: PFragBuf);
var
 P2, P3: PFragBuf;
begin
P2 := P;
while P2 <> nil do
 begin
  P3 := P2.Next;
  Mem_Free(P2);
  P2 := P3;
 end;

P := nil;
end;

procedure TNetchan.ClearFragments;
var
 I: TNetStream;
 P, P2: PFragBufDir;
begin
for I := Low(I) to High(I) do
 begin
  P := FragBufQueue[I];
  while P <> nil do
   begin
    P2 := P.Next;
    Netchan.ClearFragBufs(P.FragBuf);
    Mem_Free(P);
    P := P2;
   end;
  FragBufQueue[I] := nil;

  Netchan.ClearFragBufs(FragBufBase[I]);
  FlushIncoming(I);
 end;
end;

procedure TNetchan.Clear;
var
 I: TNetStream;
begin
  ClearFragments;
if ReliableLength > 0 then
 begin
  ReliableLength := 0;
  ReliableSequence := ReliableSequence xor 1;
 end;

SZ_Clear(NetMessage);
ClearTime := 0;

for I := Low(I) to High(I) do
 begin
  FragBufActive[I] := False;
  FragBufSequence[I] := 0;
  FragBufNum[I] := 0;
  FragBufOffset[I] := 0;
  FragBufSize[I] := 0;
  IncomingReady[I] := False;
 end;

if TempBuffer <> nil then
 Mem_FreeAndNil(TempBuffer);
TempBufferSize := 0;
end;

procedure TNetchan.Setup(ASource: TNetSrc; const AAddr: TNetAdr; ClientID: Int; ClientPtr: Pointer; Func: TFragmentSizeFunc);
begin
ClearFragments;
if TempBuffer <> nil then
 Mem_Free(TempBuffer);

MemSet(Self, SizeOf(Self), 0);
Source := ASource;
Addr := AAddr;
ClientIndex := ClientID + 1;
FirstReceived := RealTime;
LastReceived := RealTime;
Rate := 9999;
OutgoingSequence := 1;
Client := ClientPtr;
FragmentFunc := @Func;

NetMessage.Name := 'netchan->message';
NetMessage.AllowOverflow := [FSB_ALLOWOVERFLOW];
NetMessage.Data := @NetMessageBuf;
NetMessage.MaxSize := SizeOf(NetMessageBuf);
NetMessage.CurrentSize := 0;
end;

function TNetchan.CanPacket: Boolean;
begin
if (Addr.AddrType = NA_LOOPBACK) and (net_chokeloop.Value = 0) then
 begin
  ClearTime := RealTime;
  Result := True;
 end
else
 Result := ClearTime < RealTime;
end;

procedure TNetchan.UpdateFlow;
var
 I: TFlowSrc;
 Base, J: Int;
 BytesTotal: UInt;
 F: PNetchanFlowData;
 F1, F2: PNetchanFlowStats;
 Time: Double;
begin
BytesTotal := 0;
Time := 0;

for I := Low(I) to High(I) do
 begin
  F := @Flow[I];
  if RealTime - F.UpdateTime >= FLOW_UPDATETIME then
   begin
    F.UpdateTime := RealTime + FLOW_UPDATETIME;
    Base := F.InSeq - 1;

    for J := 0 to MAX_LATENT - 2 do
     begin
      F1 := @F.Stats[(Base - J) and (MAX_LATENT - 1)];
      F2 := @F.Stats[(Base - J - 1) and (MAX_LATENT - 1)];
      Inc(BytesTotal, F2.Bytes);
      Time := Time + (F1.Time - F2.Time);
     end;

    if Time <= 0 then
     F.KBRate := 0
    else
     F.KBRate := BytesTotal / Time / 1024;

    F.KBAvgRate := F.KBAvgRate * (2 / 3) + F.KBRate * (1 / 3);
   end;
 end;
end;

class procedure Netchan.PushStreams(var C: TNetchan; var SendReliable: Boolean);
var
 I: TNetStream;
 Size: UInt;
 SendNormal, HasFrag, B: Boolean;
 FB: PFragBuf;
 F: TFile;
 SendFrag: array[TNetStream] of Boolean;
 FileNameBuf: array[1..MAX_PATH_W] of LChar;
begin
C.FragSend;
for I := Low(I) to High(I) do
 SendFrag[I] := C.FragBufBase[I] <> nil;

SendNormal := C.NetMessage.CurrentSize > 0;
if SendNormal and SendFrag[NS_NORMAL] then
 begin
  SendNormal := False;
  if C.NetMessage.CurrentSize > MAX_CLIENT_FRAGSIZE then
   begin
    C.CreateFragments(C.NetMessage);
    C.NetMessage.CurrentSize := 0;
   end;
 end;

HasFrag := False;
for I := Low(I) to High(I) do
 begin
  C.FragBufActive[I] := False;
  C.FragBufSequence[I] := 0;
  C.FragBufOffset[I] := 0;
  C.FragBufSize[I] := 0;
  if SendFrag[I] then
   HasFrag := True;
 end;

if SendNormal or HasFrag then
 begin
  C.ReliableSequence := C.ReliableSequence xor 1;
  SendReliable := True;
 end;

if SendNormal then
 begin
  Move(C.NetMessageBuf, C.ReliableBuf, C.NetMessage.CurrentSize);
  C.ReliableLength := C.NetMessage.CurrentSize;
  C.NetMessage.CurrentSize := 0;
  for I := Low(I) to High(I) do
   C.FragBufOffset[I] := C.ReliableLength;
 end;

for I := Low(I) to High(I) do
 begin
  FB := C.FragBufBase[I];
  if FB = nil then
   Size := 0
  else
   if FB.FileFrag and not FB.FileBuffer then
    Size := FB.FragmentSize
   else
    Size := FB.FragMessage.CurrentSize;

  if SendFrag[I] and (FB <> nil) and (Size + C.ReliableLength <= MAX_CLIENT_FRAGSIZE) then
   begin
    C.FragBufSequence[I] := (FB.Index shl 16) or UInt16(C.FragBufNum[I]);
    if FB.FileFrag and not FB.FileBuffer then
     begin
      if FB.Compressed then
       begin
        StrLCopy(@FileNameBuf, @FB.FileName, SizeOf(FileNameBuf) - 1);
        StrLCat(@FileNameBuf, '.ztmp', SizeOf(FileNameBuf) - 1);
        B := FS_Open(F, @FileNameBuf, 'r');
       end
      else
       B := FS_Open(F, @FB.FileName, 'r');

      if B then
       begin
        FS_Seek(F, FB.FileOffset, SEEK_SET);
        FS_Read(F, Pointer(UInt(FB.FragMessage.Data) + FB.FragMessage.CurrentSize), FB.FragmentSize);
        FS_Close(F);
       end;

      Inc(FB.FragMessage.CurrentSize, FB.FragmentSize);
     end;

    Move(FB.FragMessage.Data^, Pointer(UInt(@C.ReliableBuf) + C.ReliableLength)^, FB.FragMessage.CurrentSize);
    Inc(C.ReliableLength, FB.FragMessage.CurrentSize);
    C.FragBufSize[I] := FB.FragMessage.CurrentSize;
    Netchan.UnlinkFragment(FB, C.FragBufBase[I]);
    if I = NS_NORMAL then
     Inc(C.FragBufOffset[NS_FILE], C.FragBufSize[NS_NORMAL]);

    C.FragBufActive[I] := True;
   end;
 end;
end;

procedure TNetchan.Transmit(Size: UInt; Buffer: Pointer);
var
 SB: TSizeBuf;
 SBData: array[1..MAX_PACKETLEN] of Byte;
 NetAdrBuf: array[1..64] of Byte;

 I: TNetStream;
 SendReliable, Fragmented: Boolean;
 J, FragSize: UInt;
 Seq, Seq2: Int32;
 FP: PNetchanFlowStats;
 TempRate: Double;
begin
SB.Name := 'Netchan_Transmit';
SB.AllowOverflow := [];
SB.Data := @SBData;
SB.MaxSize := SizeOf(SBData) - 3;
SB.CurrentSize := 0;

if FSB_OVERFLOWED in NetMessage.AllowOverflow then
 DPrint([NET_AdrToString(Addr, NetAdrBuf, SizeOf(NetAdrBuf)), ': Outgoing message overflow.'])
else
 begin
  SendReliable := (IncomingAcknowledged > LastReliableSequence) and
                  (IncomingReliableAcknowledged <> ReliableSequence);

  if ReliableLength = 0 then
   Netchan.PushStreams(Self, SendReliable);

  Fragmented := FragBufActive[NS_NORMAL] or FragBufActive[NS_FILE];

  Seq := OutgoingSequence or (Int(SendReliable) shl 31);
  Seq2 := IncomingSequence or (IncomingReliableSequence shl 31);
  if SendReliable and Fragmented then
   Seq := Seq or $40000000;

  MSG_WriteLong(SB, Seq);
  MSG_WriteLong(SB, Seq2);

  if SendReliable then
   begin
    if Fragmented then
     for I := Low(I) to High(I) do
      if FragBufActive[I] then
       begin
        MSG_WriteByte(SB, 1);
        MSG_WriteLong(SB, FragBufSequence[I]);
        MSG_WriteShort(SB, FragBufOffset[I]);
        MSG_WriteShort(SB, FragBufSize[I]);
       end
      else
       MSG_WriteByte(SB, 0);

    SZ_Write(SB, @ReliableBuf, ReliableLength);
    LastReliableSequence := OutgoingSequence;
   end;

  Inc(OutgoingSequence);

  if not SendReliable then
   FragSize := SB.MaxSize
  else
   FragSize := MAX_FRAGLEN;

  if SB.CurrentSize + Size > FragSize then
   DPrint('Netchan_Transmit: Unreliable message would overflow, ignoring.')
  else
   if (Buffer <> nil) and (Size > 0) then
    SZ_Write(SB, Buffer, Size);

  for J := SB.CurrentSize to 15 do
   MSG_WriteByte(SB, SVC_NOP);

  FP := @Flow[FS_TX].Stats[Flow[FS_TX].InSeq and (MAX_LATENT - 1)];
  FP.Bytes := SB.CurrentSize + UDP_OVERHEAD;
  FP.Time := RealTime;
  Inc(Flow[FS_TX].InSeq);
  UpdateFlow;

  COM_Munge2(Pointer(UInt(SB.Data) + 8), SB.CurrentSize - 8, Byte(OutgoingSequence - 1));
  NET_SendPacket(Source, SB.CurrentSize, SB.Data, Addr);

  if SV.Active and (sv_lan.Value <> 0) and (sv_lan_rate.Value > MIN_CLIENT_RATE) then
   TempRate := 1 / sv_lan_rate.Value
  else
   if Rate > 0 then
    TempRate := 1 / Rate
   else
    TempRate := 1 / 10000;

  if ClearTime <= RealTime then
   ClearTime := RealTime + (SB.CurrentSize + UDP_OVERHEAD) * TempRate
  else
   ClearTime := ClearTime + (SB.CurrentSize + UDP_OVERHEAD) * TempRate;

  if (net_showpackets.Value <> 0) and (net_showpackets.Value <> 2) then
   Print([' s --> sz=', SB.CurrentSize, ' seq=', OutgoingSequence - 1, ' ack=',  IncomingSequence, ' rel=',
          Int(SendReliable), ' tm=', SV.Time]);
 end;
end;

class function Netchan.AllocFragBuf: PFragBuf;
var
 P: PFragBuf;
begin
P := Mem_ZeroAlloc(SizeOf(TFragBuf));
if P <> nil then
 begin
  P.FragMessage.Name := 'Frag Buffer Alloc''d';
  P.FragMessage.AllowOverflow := [FSB_ALLOWOVERFLOW];
  P.FragMessage.Data := @P.Data;
  P.FragMessage.MaxSize := SizeOf(P.Data);
 end;

Result := P;
end;

class function Netchan.FindBufferByID(var Base: PFragBuf; Index: UInt; Alloc: Boolean): PFragBuf;
var
 P: PFragBuf;
begin
Result := nil;
P := Base;
while P <> nil do
 if P.Index = Index then
  begin
   Result := P;
   Exit;
  end
 else
  P := P.Next;

if Alloc then
 begin
  P := Netchan.AllocFragBuf;
  if P <> nil then
   begin
    P.Index := Index;
    Netchan.AddBufferToList(Base, P);
    Result := P;
   end;
 end;
end;

class procedure Netchan.CheckForCompletion(var C: TNetchan; Index: TNetStream; Total: UInt);
var
 P: PFragBuf;
 I: UInt;
begin
P := C.IncomingBuf[Index];
I := 0;

if P <> nil then
 begin
  repeat
   Inc(I);
   P := P.Next;
  until P = nil;

  if I = Total then
   C.IncomingReady[Index] := True;
 end;
end;

class function Netchan.ValidateHeader(Ready: Boolean; Seq, Offset, Size: UInt): Boolean;
var
 Index, Count: UInt16;
begin
Index := Seq shr 16;
Count := UInt16(Seq);

if not Ready then
 Result := True
else
 Result := (Count <= MAX_FRAGMENTS) and (Index <= Count) and (Size <= MAX_FRAGLEN) and (Offset < MAX_NETBUFLEN) and
           (MSG_ReadCount + Offset + Size <= gNetMessage.CurrentSize);
end;

function TNetchan.Process: Boolean;
var
 Seq, Ack: Int32;
 I: TNetStream;
 Rel, Fragmented, RelAck, Security: Boolean;
 FragReady: array[TNetStream] of Boolean;
 FragSeq: array[TNetStream] of UInt32;
 FragOffset, FragSize: array[TNetStream] of UInt16;
 NetAdrBuf: array[1..64] of LChar;
 FP: PNetchanFlowStats;
 P: PFragBuf;
begin
Result := False;

if not NET_CompareAdr(NetFrom, Addr) then
 Exit;

LastReceived := RealTime;

MSG_BeginReading;
Seq := MSG_ReadLong;
Ack := MSG_ReadLong;

Rel := (Seq and $80000000) > 0;
Fragmented := (Seq and $40000000) > 0;
RelAck := (Ack and $80000000) > 0;
Security := (Ack and $40000000) > 0;
Seq := Seq and $3FFFFFFF;
Ack := Ack and $3FFFFFFF;

if MSG_BadRead or Security then
 Exit;

COM_UnMunge2(Pointer(UInt(gNetMessage.Data) + 8), gNetMessage.CurrentSize - 8, Byte(Seq));
if Fragmented then
 begin
  for I := Low(I) to High(I) do
   if MSG_ReadByte > 0 then
    begin
     FragReady[I] := True;
     FragSeq[I] := MSG_ReadLong;
     FragOffset[I] := MSG_ReadShort;
     FragSize[I] := MSG_ReadShort;
    end
   else
    begin
     FragReady[I] := False;
     FragSeq[I] := 0;
     FragOffset[I] := 0;
     FragSize[I] := 0;
    end;

  for I := Low(I) to High(I) do
   if not Netchan.ValidateHeader(FragReady[I], FragSeq[I], FragOffset[I], FragSize[I]) then
    begin
     DPrint('Received a fragmented packet with invalid header, ignoring.');
     Exit;
    end;

  if FragReady[NS_NORMAL] and FragReady[NS_FILE] and (FragOffset[NS_FILE] < FragSize[NS_NORMAL]) then
   begin
    DPrint('Received a fragmented packet with invalid offset pair, ignoring.');
    Exit;
   end;
 end;

if (net_showpackets.Value <> 0) and (net_showpackets.Value <> 3) then
 Print([' s <-- sz=', gNetMessage.CurrentSize, ' seq=', Seq, ' ack=', Ack, ' rel=',
        Int(Rel), ' tm=', SV.Time]);

if Seq > IncomingSequence then
 begin
  NetDrop := Seq - IncomingSequence - 1;
  if (NetDrop > 0) and (net_showdrop.Value <> 0) then
   Print([NET_AdrToString(Addr, NetAdrBuf, SizeOf(NetAdrBuf)), ': Dropped ', NetDrop, ' packets at ', Seq, '.']);

  if (Int(RelAck) = ReliableSequence) and (IncomingAcknowledged + 1 >= LastReliableSequence) then
   ReliableLength := 0;

  IncomingSequence := Seq;
  IncomingAcknowledged := Ack;
  IncomingReliableAcknowledged := Int(RelAck);
  if Rel then
   IncomingReliableSequence := IncomingReliableSequence xor 1;

  FP := @Flow[FS_RX].Stats[Flow[FS_RX].InSeq and (MAX_LATENT - 1)];
  FP.Bytes := gNetMessage.CurrentSize + UDP_OVERHEAD;
  FP.Time := RealTime;
  Inc(Flow[FS_RX].InSeq);
  UpdateFlow;

  if not Fragmented then
   Result := True
  else
   begin
    for I := Low(I) to High(I) do
     if FragReady[I] then
      begin
       if FragSeq[I] > 0 then
        begin
         P := Netchan.FindBufferByID(IncomingBuf[I], FragSeq[I], True);
         if P = nil then
          DPrint(['Netchan_Process: Couldn''t allocate or find buffer #', FragSeq[I] shr 16, '.'])
         else
          begin
           SZ_Clear(P.FragMessage);
           SZ_Write(P.FragMessage, Pointer(UInt(gNetMessage.Data) + MSG_ReadCount + FragOffset[I]), FragSize[I]);
           if FSB_OVERFLOWED in P.FragMessage.AllowOverflow then
            begin
             DPrint('Fragment buffer overflowed.');
             Include(NetMessage.AllowOverflow, FSB_OVERFLOWED);
             Exit;
            end;
          end;

         Netchan.CheckForCompletion(Self, I, FragSeq[I] and $FFFF);
        end;

       Move(Pointer(UInt(gNetMessage.Data) + MSG_ReadCount + FragOffset[I] + FragSize[I])^,
            Pointer(UInt(gNetMessage.Data) + MSG_ReadCount + FragOffset[I])^,
            gNetMessage.CurrentSize - FragSize[I] - FragOffset[I] - MSG_ReadCount);

       Dec(gNetMessage.CurrentSize, FragSize[I]);
       if I = NS_NORMAL then
        Dec(FragOffset[NS_FILE], FragSize[NS_NORMAL]);
      end;

    Result := gNetMessage.CurrentSize > 16;
   end;
 end
else
 begin
  NetDrop := 0;
  if net_showdrop.Value <> 0 then
   if Seq = IncomingSequence then
    Print([NET_AdrToString(Addr, NetAdrBuf, SizeOf(NetAdrBuf)), ': Duplicate packet ', Seq, ' at ',  IncomingSequence, '.'])
   else
    Print([NET_AdrToString(Addr, NetAdrBuf, SizeOf(NetAdrBuf)), ': Out of order packet ', Seq, ' at ', IncomingSequence, '.'])
 end;
end;

procedure TNetchan.FragSend;
var
 I: TNetStream;
 P: PFragBufDir;
begin
for I := Low(I) to High(I) do
 if (FragBufQueue[I] <> nil) and (FragBufBase[I] = nil) then
  begin
   P := FragBufQueue[I];
   FragBufQueue[I] := P.Next;
   P.Next := nil;

   FragBufBase[I] := P.FragBuf;
   FragBufNum[I] := P.Count;
   Mem_Free(P);
  end;
end;

class procedure Netchan.AddBufferToList(var Base: PFragBuf; P: PFragBuf);
var
 P2: PFragBuf;
begin
P.Next := nil;

if Base = nil then
 Base := P
else
 begin
  P2 := Base;
  while P2.Next <> nil do
   if (P2.Next.Index shr 16) > (P.Index shr 16) then
    begin
     P.Next := P2.Next.Next;
     P2.Next := P;
     Exit;
    end
   else
    P2 := P2.Next;

  P2.Next := P;
 end;
end;

class procedure Netchan.AddFragBufToTail(Dir: PFragBufDir; var Tail: PFragBuf; P: PFragBuf);
begin
P.Next := nil;
Inc(Dir.Count);

if Dir.FragBuf = nil then
 Dir.FragBuf := P
else
 Tail.Next := P;

Tail := P;
end;

class procedure Netchan.AddDirToQueue(var Queue: PFragBufDir; Dir: PFragBufDir);
var
 P: PFragBufDir;
begin
if Queue = nil then
 Queue := Dir
else
 begin
  P := Queue;
  while P.Next <> nil do
   P := P.Next;
  P.Next := Dir;
 end;
end;

procedure Netchan_CreateFragments_(var C: TNetchan; var SB: TSizeBuf);
var
 Buf: array[1..MAX_NETBUFLEN] of Byte;
 E, DstLen, ClientFragSize, ThisSize, RemainingSize, FragIndex, DataOffset: UInt;
 Dir: PFragBufDir;
 FB, Tail: PFragBuf;
begin
if SB.CurrentSize = 0 then
 Exit;

if (net_compress.Value = 1) or (net_compress.Value >= 3) then
 begin
  DstLen := SizeOf(Buf) - SizeOf(UInt32);
  E := BZ2_bzBuffToBuffCompress(Pointer(UInt(@Buf) + SizeOf(UInt32)), @DstLen, SB.Data, SB.CurrentSize, 9, 0, 30);
  Inc(DstLen, SizeOf(UInt32));
  if (E = BZ_OK) and (DstLen <= SB.MaxSize) then
   begin
    PUInt32(@Buf)^ := BZIP2_TAG;
    DPrint(['Compressing split packet (', SB.CurrentSize, ' -> ', DstLen, ' bytes).']);
    SZ_Clear(SB);
    SZ_Write(SB, @Buf, DstLen);
   end;
 end;

if (@C.FragmentFunc <> nil) and (C.Client <> nil) then
 ClientFragSize := C.FragmentFunc(C.Client)
else
 ClientFragSize := DEF_CLIENT_FRAGSIZE;

Dir := Mem_ZeroAlloc(SizeOf(TFragBufDir));
FragIndex := 1;
DataOffset := 0;
Tail := nil;

RemainingSize := SB.CurrentSize;
while RemainingSize > 0 do
 begin
  if RemainingSize < ClientFragSize then
   ThisSize := RemainingSize
  else
   ThisSize := ClientFragSize;

  FB := Netchan.AllocFragBuf;
  if FB = nil then
   begin
    DPrint('Couldn''t allocate fragment buffer.');
    Netchan.ClearFragBufs(Dir.FragBuf);
    Mem_Free(Dir);

    if C.Client <> nil then
     SV_DropClient(PClient(C.Client)^, False, 'Server failed to allocate a fragment buffer.');
    Exit;
   end;

  FB.Index := FragIndex;
  Inc(FragIndex);
  SZ_Write(FB.FragMessage, Pointer(UInt(SB.Data) + DataOffset), ThisSize);
  Inc(DataOffset, ThisSize);
  Dec(RemainingSize, ThisSize);

  Netchan.AddFragBufToTail(Dir, Tail, FB);
 end;

Netchan.AddDirToQueue(C.FragBufQueue[NS_NORMAL], Dir);
end;

procedure TNetchan.CreateFragments(var SB: TSizeBuf);
begin
if NetMessage.CurrentSize > 0 then
 begin
  Netchan_CreateFragments_(Self, NetMessage);
  NetMessage.CurrentSize := 0;
 end;

Netchan_CreateFragments_(Self, SB);
end;

class function Netchan.CompressBuf(SrcBuf: Pointer; SrcSize: UInt; out DstBuf: Pointer; out DstSize: UInt): Boolean;
var
 E: UInt;
begin
Result := False;
DstSize := SrcSize + SrcSize div 100 + 600;
DstBuf := Mem_Alloc(DstSize);
if DstBuf <> nil then
 begin
  E := BZ2_bzBuffToBuffCompress(DstBuf, @DstSize, SrcBuf, SrcSize, 9, 0, 30);
  if E = BZ_OK then
   Result := True
  else
   Mem_Free(DstBuf);
 end;
end;

procedure TNetchan.CreateFileFragmentsFromBuffer(Name: PLChar; Buffer: Pointer; Size: UInt);
var
 Compressed, NeedHeader: Boolean;
 DstBuf: Pointer;
 DstSize, ClientFragSize, FragIndex, ThisSize, FileOffset, RemainingSize: UInt;
 Dir: PFragBufDir;
 FB, Tail: PFragBuf;
begin
if Size = 0 then
 Exit;

Compressed := (net_compress.Value >= 2) and Netchan.CompressBuf(Buffer, Size, DstBuf, DstSize);
if Compressed then
 DPrint(['Compressed "', Name, '" for transmission (', Size, ' -> ', DstSize, ').'])
else
 begin
  DstBuf := Buffer;
  DstSize := Size;
 end;

if (@FragmentFunc <> nil) and (Client <> nil) then
 ClientFragSize := FragmentFunc(Client)
else
 ClientFragSize := DEF_CLIENT_FRAGSIZE;

Dir := Mem_ZeroAlloc(SizeOf(TFragBufDir));
FragIndex := 1;
NeedHeader := True;
FileOffset := 0;
Tail := nil;

RemainingSize := DstSize;
while RemainingSize > 0 do
 begin
  if RemainingSize < ClientFragSize then
   ThisSize := RemainingSize
  else
   ThisSize := ClientFragSize;

  FB := Netchan.AllocFragBuf;
  if FB = nil then
   begin
    DPrint('Couldn''t allocate fragment buffer.');
    Netchan.ClearFragBufs(Dir.FragBuf);
    Mem_Free(Dir);
    if Compressed then
     Mem_Free(DstBuf);

    if Client <> nil then
     SV_DropClient(PClient(Client)^, False, 'Server failed to allocate a fragment buffer.');
    Exit;
   end;

  FB.Index := FragIndex;
  Inc(FragIndex);

  if NeedHeader then
   begin
    NeedHeader := False;
    MSG_WriteString(FB.FragMessage, Name);
    if Compressed then
     MSG_WriteString(FB.FragMessage, 'bz2')
    else
     MSG_WriteString(FB.FragMessage, 'uncompressed');
    MSG_WriteLong(FB.FragMessage, Size);

    if ThisSize > FB.FragMessage.CurrentSize then
     Dec(ThisSize, FB.FragMessage.CurrentSize)
    else
     ThisSize := 0;
   end;

  FB.FragmentSize := ThisSize;
  FB.FileOffset := FileOffset;
  FB.FileFrag := True;
  FB.FileBuffer := True;

  MSG_WriteBuffer(FB.FragMessage, ThisSize, Pointer(UInt(DstBuf) + FileOffset));
  Inc(FileOffset, ThisSize);
  Dec(RemainingSize, ThisSize);

  Netchan.AddFragBufToTail(Dir, Tail, FB);
 end;

Netchan.AddDirToQueue(FragBufQueue[NS_FILE], Dir);

if Compressed then
 Mem_Free(DstBuf);
end;

class function Netchan.GetFileInfo(var C: TNetchan; Name: PLChar; out Size, CompressedSize: UInt; out Compressed: Boolean): Boolean;
var
 NetAdrBuf: array[1..64] of LChar;
 Buf: array[1..MAX_PATH_W] of LChar;
 DstSize: UInt;
 SrcBuf, DstBuf: Pointer;
 F, F2: TFile;
begin
Result := False;
StrLCopy(@Buf, Name, SizeOf(Buf) - 1);
StrLCat(@Buf, '.ztmp', SizeOf(Buf) - 1);
CompressedSize := FS_SizeByName(@Buf);
if (CompressedSize > 0) and (FS_GetFileTime(@Buf) >= FS_GetFileTime(Name)) then
 begin
  Size := FS_SizeByName(Name);
  if Size = 0 then
   DPrint(['Unable to open "', Name, '" for transfer to ', NET_AdrToString(C.Addr, NetAdrBuf, SizeOf(NetAdrBuf)), '.'])
  else
   if Size > sv_filetransfermaxsize.Value then
    DPrint(['File "', Name, '" is too big to transfer to ', NET_AdrToString(C.Addr, NetAdrBuf, SizeOf(NetAdrBuf)), '.'])
   else
    begin
     Compressed := True;
     Result := True;
    end;
 end
else
 if not FS_Open(F, Name, 'r') then
  DPrint(['Unable to open "', Name, '" for transfer to ', NET_AdrToString(C.Addr, NetAdrBuf, SizeOf(NetAdrBuf)), '.'])
 else
  begin
   Size := FS_Size(F);
   if Size > sv_filetransfermaxsize.Value then
    DPrint(['File "', Name, '" is too big to transfer to ', NET_AdrToString(C.Addr, NetAdrBuf, SizeOf(NetAdrBuf)), '.'])
   else
    begin
     CompressedSize := Size;
     Result := True;
     if (sv_filetransfercompression.Value = 0) and (net_compress.Value < 2) then
      Compressed := False
     else
      begin
       SrcBuf := Mem_Alloc(Size);
       if SrcBuf = nil then
        DPrint(['Out of memory while caching compressed version of "', Name, '".'])
       else
        begin
         if FS_Read(F, SrcBuf, Size) <> Size then
          DPrint(['File read error while caching compressed version of "', Name, '".'])
         else
          if Netchan.CompressBuf(SrcBuf, Size, DstBuf, DstSize) then
           begin
            if FS_Open(F2, @Buf, 'wo') then
             begin
              DPrint(['Creating compressed version of file "', Name, '" (', Size, ' -> ', DstSize, ').']);
              FS_Write(F2, DstBuf, DstSize);
              FS_Close(F2);
              CompressedSize := DstSize;
              Compressed := True;
             end;

            Mem_Free(DstBuf);
           end;

         Mem_Free(SrcBuf);
        end;
      end;
    end;

   FS_Close(F);
  end;
end;

function TNetchan.CreateFileFragments(Name: PLChar): Boolean;
var
 Compressed, NeedHeader: Boolean;
 ClientFragSize, FragIndex, Size, ThisSize, FileOffset, RemainingSize: UInt;
 Dir: PFragBufDir;
 FB, Tail: PFragBuf;
begin
Result := False;
if not Netchan.GetFileInfo(Self, Name, Size, RemainingSize, Compressed) then
 Exit;

if (@FragmentFunc <> nil) and (Client <> nil) then
 ClientFragSize := FragmentFunc(Client)
else
 ClientFragSize := DEF_CLIENT_FRAGSIZE;

Dir := Mem_ZeroAlloc(SizeOf(TFragBufDir));
FragIndex := 1;
NeedHeader := True;
FileOffset := 0;
Tail := nil;

while RemainingSize > 0 do
 begin
  if RemainingSize < ClientFragSize then
   ThisSize := RemainingSize
  else
   ThisSize := ClientFragSize;

  FB := Netchan.AllocFragBuf;
  if FB = nil then
   begin
    DPrint('Couldn''t allocate fragment buffer.');
    Netchan.ClearFragBufs(Dir.FragBuf);
    Mem_Free(Dir);

    if Client <> nil then
     SV_DropClient(PClient(Client)^, False, 'Server failed to allocate a fragment buffer.');
    Exit;
   end;

  FB.Index := FragIndex;
  Inc(FragIndex);

  if NeedHeader then
   begin
    NeedHeader := False;
    MSG_WriteString(FB.FragMessage, Name);
    if Compressed then
     MSG_WriteString(FB.FragMessage, 'bz2')
    else
     MSG_WriteString(FB.FragMessage, 'uncompressed');
    MSG_WriteLong(FB.FragMessage, Size);

    if ThisSize > FB.FragMessage.CurrentSize then
     Dec(ThisSize, FB.FragMessage.CurrentSize)
    else
     ThisSize := 0;
   end;

  FB.FragmentSize := ThisSize;
  FB.FileOffset := FileOffset;
  FB.FileFrag := True;
  FB.Compressed := Compressed;
  StrLCopy(@FB.FileName, Name, MAX_PATH_A - 1);

  Inc(FileOffset, ThisSize);
  Dec(RemainingSize, ThisSize);

  Netchan.AddFragBufToTail(Dir, Tail, FB);
 end;

Netchan.AddDirToQueue(FragBufQueue[NS_FILE], Dir);
Result := True;
end;

procedure TNetchan.FlushIncoming(Stream: TNetStream);
var
 P, P2: PFragBuf;
begin
SZ_Clear(gNetMessage);
MSG_ReadCount := 0;

P := IncomingBuf[Stream];
while P <> nil do
 begin
  P2 := P.Next;
  Mem_Free(P);
  P := P2;
 end;

IncomingBuf[Stream] := nil;
IncomingReady[Stream] := False;
end;

function TNetchan.CopyNormalFragments: Boolean;
var
 P, P2: PFragBuf;
 DstSize: UInt;
 Buf: array[1..MAX_NETBUFLEN] of Byte;
begin
Result := False;

if IncomingReady[NS_NORMAL] then
 if IncomingBuf[NS_NORMAL] <> nil then
  begin
   SZ_Clear(gNetMessage);

   P := IncomingBuf[NS_NORMAL];
   while P <> nil do
    begin
     P2 := P.Next;
     SZ_Write(gNetMessage, P.FragMessage.Data, P.FragMessage.CurrentSize);
     Mem_Free(P);
     P := P2;
    end;

   IncomingBuf[NS_NORMAL] := nil;
   IncomingReady[NS_NORMAL] := False;

   if FSB_OVERFLOWED in gNetMessage.AllowOverflow then
    begin
     DPrint('Netchan_CopyNormalFragments: Fragment buffer overflowed, ignoring.');
     SZ_Clear(gNetMessage);
    end
   else
    if PUInt32(gNetMessage.Data)^ <> BZIP2_TAG then
     Result := True
    else
     begin
      DstSize := SizeOf(Buf);
      if BZ2_bzBuffToBuffDecompress(@Buf, @DstSize, Pointer(UInt(gNetMessage.Data) + SizeOf(UInt32)), gNetMessage.CurrentSize - SizeOf(UInt32), 1, 0) = BZ_OK then
       begin
        Move(Buf, gNetMessage.Data^, DstSize);
        gNetMessage.CurrentSize := DstSize;
        Result := True;
       end
      else
       SZ_Clear(gNetMessage);
     end;
  end
 else
  begin
   DPrint('Netchan_CopyNormalFragments: Called with no fragments readied.');
   IncomingReady[NS_NORMAL] := False;
  end;
end;

class function Netchan.DecompressIncoming(FileName: PLChar; var Src: Pointer; var TotalSize: UInt; IncomingSize: UInt): Boolean;
var
 P: Pointer;
begin
Result := False;
if IncomingSize > sv_filereceivemaxsize.Value then
 DPrint(['Incoming decompressed size for file "', PLChar(FileName), '" is too big, ignoring.'])
else
 begin
  P := Mem_Alloc(IncomingSize + 1);
  DPrint(['Decompressing file "', PLChar(FileName), '" (', TotalSize, ' -> ', IncomingSize, ').']);
  if BZ2_bzBuffToBuffDecompress(P, @IncomingSize, Src, TotalSize, 1, 0) <> BZ_OK then
   begin
    DPrint(['Decompression failed for incoming file "', PLChar(FileName), '".']);
    Mem_Free(P);
   end
  else
   begin
    Mem_Free(Src);
    Src := P;
    TotalSize := IncomingSize;
    Result := True;
   end;
 end;
end;

function TNetchan.CopyFileFragments: Boolean;
var
 P, P2: PFragBuf;
 IncomingSize, TotalSize, CurrentSize: UInt;
 TempFileName: array[1..MAX_PATH_A] of LChar;
 Compressed: Boolean;
 Src, Data: Pointer;
begin
Result := False;

if IncomingReady[NS_FILE] then
 if IncomingBuf[NS_FILE] <> nil then
  begin
   SZ_Clear(gNetMessage);
   MSG_BeginReading;

   P := IncomingBuf[NS_FILE];
   if P.FragMessage.CurrentSize > gNetMessage.MaxSize then
    DPrint('File fragment buffer overflowed.')
   else
    begin
     if P.FragMessage.CurrentSize > 0 then
      SZ_Write(gNetMessage, P.FragMessage.Data, P.FragMessage.CurrentSize);

     StrLCopy(@FileName, MSG_ReadString, SizeOf(FileName) - 1);
     Compressed := StrIComp(MSG_ReadString, 'bz2') = 0;
     IncomingSize := MSG_ReadLong;

     if MSG_BadRead then
      DPrint('File fragment received with invalid header.')
     else
      if FileName[1] = #0 then
       DPrint('File fragment received with no filename.')
      else
       if not IsSafeFile(@FileName) then
        DPrint('File fragment received with unsafe path.')
       else
        if IncomingSize > sv_filereceivemaxsize.Value then
         DPrint('File fragment received with too big size.')
        else
         begin
          StrLCopy(@FileName, @TempFileName, SizeOf(FileName) - 1);

          if FileName[1] <> '!' then
           begin
            if sv_receivedecalsonly.Value <> 0 then
             begin
              DPrint(['Received a non-decal file "', PLChar(@FileName), '", ignored.']);
              FlushIncoming(NS_FILE);
              Exit;
             end;

            if FS_FileExists(@FileName) then
             begin
              DPrint(['Can''t download "', PLChar(@FileName), '", already exists.']);
              FlushIncoming(NS_FILE);
              Result := True;
              Exit;
             end;

            COM_CreatePath(@FileName);
           end;

          TotalSize := 0;
          while P <> nil do
           begin
            Inc(TotalSize, P.FragMessage.CurrentSize);
            P := P.Next;
           end;

          if TotalSize > MSG_ReadCount then
           Dec(TotalSize, MSG_ReadCount)
          else
           TotalSize := 0;

          Src := Mem_ZeroAlloc(TotalSize + 1);
          if Src = nil then
           DPrint(['Buffer allocation failed on ', TotalSize + 1, ' bytes.'])
          else
           begin
            CurrentSize := 0;

            P := IncomingBuf[NS_FILE];
            while P <> nil do
             begin
              P2 := P.Next;
              if P = IncomingBuf[NS_FILE] then
               begin
                Dec(P.FragMessage.CurrentSize, MSG_ReadCount);
                Data := Pointer(UInt(P.FragMessage.Data) + MSG_ReadCount);
               end
              else
               Data := P.FragMessage.Data;

              Move(Data^, Pointer(UInt(Src) + CurrentSize)^, P.FragMessage.CurrentSize);
              Inc(CurrentSize, P.FragMessage.CurrentSize);
              Mem_Free(P);
              P := P2;
             end;

            IncomingBuf[NS_FILE] := nil;
            IncomingReady[NS_FILE] := False;

            if not Compressed or Netchan.DecompressIncoming(@FileName, Src, TotalSize, IncomingSize) then
             begin
              if TempFileName[1] = '!' then
               begin
                if TempBuffer <> nil then
                 Mem_FreeAndNil(TempBuffer);
                TempBuffer := Src;
                TempBufferSize := TotalSize;
               end
              else
               begin
                COM_WriteFile(@TempFileName, Src, TotalSize);
                Mem_Free(Src);
               end;

              SZ_Clear(gNetMessage);
              MSG_BeginReading;
              IncomingBuf[NS_FILE] := nil;
              IncomingReady[NS_FILE] := False;
              Result := True;
              Exit;
             end;

            Mem_Free(Src);
           end;
         end;
    end;

   FlushIncoming(NS_FILE);
  end
 else
  begin
   DPrint('Netchan_CopyFileFragments: Called with no fragments readied.');
   IncomingReady[NS_FILE] := False;
  end;
end;

function TNetchan.IsIncomingReady: Boolean;
begin
  Result := IncomingReady[NS_NORMAL] or IncomingReady[NS_FILE];
end;

class procedure Netchan.Init;
begin
CVar_RegisterVariable(net_showpackets);
CVar_RegisterVariable(net_showdrop);
CVar_RegisterVariable(net_chokeloop);
CVar_RegisterVariable(sv_filetransfercompression);
CVar_RegisterVariable(sv_filetransfermaxsize);
CVar_RegisterVariable(sv_filereceivemaxsize);
CVar_RegisterVariable(sv_receivedecalsonly);
CVar_RegisterVariable(net_compress);
end;
                    
end.
