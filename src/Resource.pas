unit Resource;    // rename to SVRes

interface

uses
  SysUtils, Default, SDK, Client, SizeBuf;

procedure SV_SetResourceLists(var C: TClient);
procedure SV_ClearResourceLists(var C: TClient);

procedure SV_ClearCustomizationList(var List: TCustomization);

procedure SV_CreateResourceList;
procedure SV_CreateGenericResources;
procedure SV_TransferConsistencyInfo;
procedure SV_RequestMissingResourcesFromClients;

procedure SV_ParseResourceList(var C: TClient);
procedure SV_ParseConsistencyResponse(var C: TClient);
procedure SV_ProcessFile(var C: TClient; Name: PLChar);

procedure SV_BeginFileDownload_F; cdecl;

var
 sv_allowdownload: TCVar = (Name: 'sv_allowdownload'; Data: '1'; Flags: [FCVAR_SERVER]);
 sv_allowupload: TCVar = (Name: 'sv_allowupload'; Data: '1'; Flags: [FCVAR_SERVER]);

 sv_uploadmax: TCVar = (Name: 'sv_uploadmax'; Data: '0.5'; Flags: [FCVAR_SERVER]);
 sv_uploadmaxnum: TCVar = (Name: 'sv_uploadmaxnum'; Data: '16'; Flags: [FCVAR_SERVER]);
 sv_uploadmaxsingle: TCVar = (Name: 'sv_uploadmaxsingle'; Data: '0.256'; Flags: [FCVAR_SERVER]);
 sv_uploaddecalsonly: TCVar = (Name: 'sv_uploaddecalsonly'; Data: '1'; Flags: [FCVAR_SERVER]);

 sv_send_logos: TCVar = (Name: 'sv_send_logos'; Data: '1');
 sv_send_resources: TCVar = (Name: 'sv_send_resources'; Data: '1');
 
implementation

uses Common, Console, Decal, Encode, FileSys, GameLib, Host, MathLib,
  Memory, MsgBuf, Network, HPAK, Renderer, SVClient, SVExport, SVMain,
  SysMain, Netchan;

procedure SV_AddToResourceList(var Res, List: TResource);
begin
if (Res.Prev <> nil) or (Res.Next <> nil) then
 Print('SV_AddToResourceList: Resource already linked.')
else
 begin
  Res.Prev := List.Prev;
  List.Prev.Next := @Res;
  List.Prev := @Res;
  Res.Next := @List;
 end;
end;

procedure SV_RemoveFromResourceList(var Res: TResource);
begin
Res.Prev.Next := Res.Next;
Res.Next.Prev := Res.Prev;
Res.Prev := nil;
Res.Next := nil;
end;

procedure SV_ClearResourceList(var Res: TResource);
var
 P, P2: PResource;
begin
P := Res.Next;
while (P <> nil) and (P <> @Res) do
 begin
  P2 := P.Next;
  Mem_Free(P);
  P := P2;
 end;

Res.Prev := @Res;
Res.Next := @Res;
end;

procedure SV_MoveToOnHandList(var C: TClient; var Res: TResource);
begin
SV_RemoveFromResourceList(Res);
SV_AddToResourceList(Res, C.DownloadList);
end;

procedure SV_SetResourceLists(var C: TClient);
begin
C.DownloadList.Next := @C.DownloadList;
C.DownloadList.Prev := @C.DownloadList;
C.UploadList.Next := @C.UploadList;
C.UploadList.Prev := @C.UploadList;
end;

procedure SV_ClearResourceLists(var C: TClient);
begin
SV_ClearResourceList(C.DownloadList);
SV_ClearResourceList(C.UploadList);
end;

procedure SV_ClearCustomization(var C: TCustomization);
begin
if C.InUse then
 begin
  if C.Buffer <> nil then
   Mem_Free(C.Buffer);

  if C.Info <> nil then
   begin
    if C.Resource.ResourceType = RT_DECAL then
     Draw_FreeWAD(C.Info);

    Mem_Free(C.Info);
   end;
 end;
end;

procedure SV_ClearCustomizationList(var List: TCustomization);
var
 P, P2: PCustomization;
begin
P := List.Next;
while P <> nil do
 begin
  P2 := P.Next;
  SV_ClearCustomization(P^);
  Mem_Free(P);
  P := P2;
 end;

List.Next := nil;                                 
end;

function InitCustomDecal(var C: TCustomization; const Resource: TResource; Flags: TCustFlags; out LumpCount: UInt): Boolean;
var
 Decal: PCacheWAD;
begin
if (Resource.DownloadSize >= 1024) and (Resource.DownloadSize <= 128*160) then
 begin
  Decal := Mem_ZeroAlloc(SizeOf(TCacheWAD));
  if Decal <> nil then
   begin
    if CustomDecal_Init(Decal, C.Buffer, Resource.DownloadSize, C.Resource.PlayerNum) then
     begin
      if Decal.DecalCount > 0 then
       begin
        C.Info := Decal;
        C.Translated := True;
        C.UserData1 := 0;
        C.UserData2 := Decal.DecalCount;
        LumpCount := Decal.DecalCount;
        if FCUST_WIPEDATA in Flags then
         begin
          Draw_FreeWAD(Decal);
          Mem_FreeAndNil(C.Info);
         end;

        Result := True;
        Exit;
       end;

      Draw_FreeWAD(Decal);
     end;

    Mem_Free(Decal);
   end;
 end;

Result := False;
end;

function ProcessResource(var C: TCustomization; const Resource: TResource; PlayerIndex: Int; Flags: TCustFlags; out LumpCount: UInt): Boolean;
begin
Result := True;
if (RES_CUSTOM in C.Resource.Flags) and (C.Resource.ResourceType = RT_DECAL) then
 begin
  C.Resource.PlayerNum := PlayerIndex;
  if not CustomDecal_Validate(C.Buffer, Resource.DownloadSize) then
   Result := False
  else
   if not (FCUST_IGNOREINIT in Flags) then
    Result := InitCustomDecal(C, Resource, Flags, LumpCount);
 end;
end;

function SV_CreateCustomization(var List: TCustomization; const Resource: TResource; PlayerIndex: Int; Flags: TCustFlags; out Customization: PCustomization; out LumpCount: UInt): Boolean;
var
 C: PCustomization;
begin
C := Mem_ZeroAlloc(SizeOf(TCustomization));

if C <> nil then
 begin
  Move(Resource, C.Resource, SizeOf(C.Resource));

  if Resource.DownloadSize > 0 then
   begin
    C.InUse := True;

    if not (FCUST_FROMHPAK in Flags) then
     C.Buffer := COM_LoadFile(@Resource.Name, FILE_ALLOC_MEMORY, nil)
    else
     if not HPAK_GetDataPointer('custom.hpk', Resource, @C.Buffer, nil) then
      C.Buffer := nil;

    if C.Buffer <> nil then
     begin
      if ProcessResource(C^, Resource, PlayerIndex, Flags, LumpCount) then
       begin
        C.Next := List.Next;
        List.Next := C;

        Customization := C;
        Result := True;
        Exit;
       end;

      if FCUST_FROMHPAK in Flags then
       Mem_Free(C.Buffer)
      else
       COM_FreeFile(C.Buffer);
     end;
   end;

  Mem_Free(C);
 end;

Customization := nil;
LumpCount := 0;
Result := False;
end;

function SV_SizeOfResourceList(const List: TResource; var Pack: TResourcePackSize): UInt;
var
 P: PResource;
begin
Result := 0;
MemSet(Pack, SizeOf(Pack), 0);

P := List.Next;
while P <> @List do
 begin
  Inc(Result, P.DownloadSize);
  if (P.ResourceType = RT_MODEL) and (P.Index = 1) then
   Inc(Pack[RT_WORLD], P.DownloadSize)
  else
   Inc(Pack[P.ResourceType], P.DownloadSize);

  P := P.Next;
 end;
end;

procedure SV_PropagateCustomizations(var Dest: TClient);
var
 I: Int;
 P: PCustomization;
 C: PClient;
begin
for I := 0 to SVS.MaxClients - 1 do
 begin
  C := @SVS.Clients[I];
  if (C.Active or C.Spawned) and C.Connected and not C.FakeClient then
   begin
    P := C.Customization.Next;
    while P <> nil do
     begin
      if P.InUse then
       begin
        Dest.Netchan.NetMessage.Write<UInt8>(SVC_CUSTOMIZATION);
        Dest.Netchan.NetMessage.Write<UInt8>(I);
        Dest.Netchan.NetMessage.Write<UInt8>(Byte(P.Resource.ResourceType));
        Dest.Netchan.NetMessage.WriteString(@P.Resource.Name);
        Dest.Netchan.NetMessage.Write<Int16>(P.Resource.Index);
        Dest.Netchan.NetMessage.Write<Int32>(P.Resource.DownloadSize);
        Dest.Netchan.NetMessage.Write<UInt8>(Byte(P.Resource.Flags));
        if RES_CUSTOM in P.Resource.Flags then
         Dest.Netchan.NetMessage.Write(@P.Resource.MD5Hash, SizeOf(P.Resource.MD5Hash));
       end;
       
      P := P.Next;
     end;
   end;
 end;
end;

procedure SV_Customization(var C: TClient; const Res: TResource; SkipSelf: Boolean);
var
 I: Int;
 Index: UInt;
 P: PClient;
begin
Index := (UInt(@C) - UInt(SVS.Clients)) div SizeOf(TClient);

for I := 0 to SVS.MaxClients - 1 do
 begin
  P := @SVS.Clients[I];
  if (P.Active or P.Spawned) and P.Connected and not P.FakeClient and (not SkipSelf or (UInt(I) <> Index)) then
   begin
    P.Netchan.NetMessage.Write<UInt8>(SVC_CUSTOMIZATION);
    P.Netchan.NetMessage.Write<UInt8>(Index);
    P.Netchan.NetMessage.Write<UInt8>(Byte(Res.ResourceType));
    P.Netchan.NetMessage.WriteString(@Res.Name);
    P.Netchan.NetMessage.Write<Int16>(Res.Index);
    P.Netchan.NetMessage.Write<Int32>(Res.DownloadSize);
    P.Netchan.NetMessage.Write<UInt8>(Byte(Res.Flags));
    if RES_CUSTOM in Res.Flags then
     P.Netchan.NetMessage.Write(@Res.MD5Hash, SizeOf(Res.MD5Hash));
   end;
 end;
end;

function IsResourceInCustom(C: PCustomization; Hash: Pointer): Boolean;
begin
C := C.Next;
while C <> nil do
 if CompareMem(Hash, @C.Resource.MD5Hash, SizeOf(C.Resource.MD5Hash)) then
  begin
   Result := True;
   Exit;
  end
 else
  C := C.Next;

Result := False;
end;

procedure SV_CreateCustomizationList(var C: TClient);
var
 C2: PCustomization;
 P: PResource;
 LumpCount: UInt;
begin
SV_ClearCustomizationList(C.Customization);

P := C.DownloadList.Next;
while P <> @C.DownloadList do
 begin
  if IsResourceInCustom(@C.Customization, @P.MD5Hash) then
   DPrint(['SV_CreateCustomizationList: Ignoring duplicate resource for player "', PLChar(@C.NetName), '".'])
  else
   begin
    LumpCount := 0;
    if SV_CreateCustomization(C.Customization, P^, -1, [FCUST_FROMHPAK, FCUST_WIPEDATA], C2, LumpCount) then
     begin
      C2.UserData2 := LumpCount;
      DLLFunctions.PlayerCustomization(C.Entity^, C2);
     end
    else
     if sv_allowupload.Value = 0 then
      Print(['Ignoring custom decal from "', PLChar(@C.NetName), '", sv_allowupload is set to 0.'])
     else
      Print(['Ignoring invalid custom decal from "', PLChar(@C.NetName), '".']);
   end;

  P := P.Next;
 end;
end;

function SV_CheckFile(var SB: TSizeBuf; Name: PLChar): Boolean;
var
 Buf: array[1..128] of LChar;
 S: PLChar;
 Res: TResource;
 MD5S: TMD5HashStr;
begin
MemSet(Res, SizeOf(Res), 0);
if (StrLComp(Name, '!MD5', 4) = 0) and MD5_IsValid(PLChar(UInt(Name) + 4)) then
 begin
  COM_HexConvert(PLChar(UInt(Name) + 4), 32, @Res.MD5Hash);
  if HPAK_GetDataPointer('custom.hpk', Res, nil, nil) then
   begin
    Result := True;
    Exit;
   end;
 end;

if sv_allowupload.Value = 0 then
 Result := True
else
 begin
  S := StrECopy(@Buf, 'upload "!MD5');
  MD5_Print(Res.MD5Hash, MD5S);
  S := StrECopy(S, @MD5S);
  StrCopy(S, '"'#10);

  SB.Write<UInt8>(SVC_STUFFTEXT);
  SB.WriteString(@Buf);
  Result := False;
 end;
end;

procedure SV_RegisterResources(var C: TClient);
var
 P: PResource;
begin
SV_CreateCustomizationList(C);

P := C.DownloadList.Next;
while P <> @C.DownloadList do
 begin
  SV_Customization(C, P^, True);
  P := P.Next;
 end;

C.HasMissingResources := False;
end;

function SV_UploadComplete(var C: TClient): Boolean;
begin
if C.UploadList.Next = @C.UploadList then
 begin
  SV_RegisterResources(C);
  SV_PropagateCustomizations(C);
  if sv_allowupload.Value <> 0 then
   DPrint('Custom resource propagation complete.');

  C.UploadComplete := True;
  Result := True;
 end
else
 Result := False;
end;

procedure SV_RequestMissingResourcesFromClients;
var
 I: Int;
 C: PClient;
begin
for I := 0 to SVS.MaxClients - 1 do
 begin
  C := @SVS.Clients[I];
  if (C.Active or C.Spawned) and C.Connected and not C.FakeClient and C.HasMissingResources and not C.UploadComplete then
   SV_UploadComplete(C^);
 end;
end;

function SV_EstimateNeededResources(const C: TClient): UInt;
var
 P: PResource;
begin
Result := 0;
P := C.UploadList.Next;
while P <> @C.UploadList do
 begin
  if (P.ResourceType = RT_DECAL) and (P.DownloadSize > 0) and not HPAK_ResourceForHash('custom.hpk', @P.MD5Hash, nil) then
   begin
    Inc(Result, P.DownloadSize);
    Include(P.Flags, RES_WASMISSING);
   end;

  P := P.Next;
 end;
end;

procedure SV_BatchUploadRequest(var C: TClient);
var
 P, P2: PResource;
 Buf: array[1..128] of LChar;
 MD5S: TMD5HashStr;
 S: PLChar;
begin                                     
P := C.UploadList.Next;
while P <> @C.UploadList do
 begin
  P2 := P.Next;
  if not (RES_WASMISSING in P.Flags) then
   SV_MoveToOnHandList(C, P^)
  else
   if P.ResourceType = RT_DECAL then
    if RES_CUSTOM in P.Flags then
     begin
      MD5_Print(P.MD5Hash, MD5S);
      S := StrECopy(@Buf, '!MD5');
      StrCopy(S, @MD5S);
      if SV_CheckFile(C.Netchan.NetMessage, @Buf) then
       SV_MoveToOnHandList(C, P^);
     end
    else
     begin
      Print('SV_BatchUploadRequest: Non-customization in upload queue.');
      SV_MoveToOnHandList(C, P^);
     end;

  P := P2;
 end;
end;




procedure SV_CheckUploadCVars;
begin
if (sv_allowupload.Value <> 0) and (sv_allowupload.Value <> 1) then
 CVar_DirectSet(sv_allowupload, '1');
if (sv_uploaddecalsonly.Value <> 0) and (sv_uploaddecalsonly.Value <> 1) then
 CVar_DirectSet(sv_uploaddecalsonly, '1');

if sv_uploadmaxsingle.Value < 0 then
 CVar_DirectSet(sv_uploadmaxsingle, '0');
if sv_uploadmax.Value < 0 then
 CVar_DirectSet(sv_uploadmax, '0');
if sv_uploadmaxnum.Value < 0 then
 CVar_DirectSet(sv_uploadmaxnum, '0');
end;

procedure SV_ParseResourceList(var C: TClient);
var
 DecalsOnly: Boolean;
 I, J, NumRes, MaxAllowed: Int;
 Pack: TResourcePackSize;
 Size, EstSize, MaxSize: UInt;
 Res: TResource;
 P: PResource;
begin
SV_ClearResourceLists(C);

SV_CheckUploadCVars;
MaxSize := Trunc(sv_uploadmaxsingle.Value * (1024 * 1024));
DecalsOnly := sv_uploaddecalsonly.Value <> 0;
MaxAllowed := Trunc(sv_uploadmaxnum.Value);
J := 0;

NumRes := MSG_ReadShort;
for I := 0 to NumRes - 1 do
 begin
  MemSet(Res, SizeOf(Res), 0);
  StrLCopy(@Res.Name, MSG_ReadString, SizeOf(Res.Name) - 1);
  PByte(@Res.ResourceType)^ := MSG_ReadByte;
  Res.Index := MSG_ReadShort;
  Res.DownloadSize := MSG_ReadLong;
  Byte(Res.Flags) := MSG_ReadByte;
  if RES_CUSTOM in Res.Flags then
   MSG_ReadBuffer(SizeOf(Res.MD5Hash), @Res.MD5Hash);

  Exclude(Res.Flags, RES_WASMISSING);
  Exclude(Res.Flags, RES_PADDING);

  if MSG_BadRead then
   begin
    DPrint(['SV_ParseResourceList: "', PLChar(@C.NetName), '" sent bad resource data.']);
    SV_DropClient(C, False, 'Bad resource list.');
    Exit;
   end
  else
   if Res.ResourceType >= RT_WORLD then
    begin
     DPrint(['SV_ParseResourceList: "', PLChar(@C.NetName), '" sent bad resource type.']);
     SV_DropClient(C, False, 'Bad resource list.');
     Exit;
    end
   else
    if Res.DownloadSize > MaxSize then
     DPrint(['SV_ParseResourceList: "', PLChar(@C.NetName), '" sent an oversized resource, ignoring.'])
    else
     if DecalsOnly and (Res.ResourceType <> RT_DECAL) then
      DPrint(['SV_ParseResourceList: "', PLChar(@C.NetName), '" sent a non-decal resource, ignoring.'])
     else
      if (sv_allowupload.Value <> 0) and ((MaxAllowed = 0) or (J < MaxAllowed)) then
       begin
        P := Mem_Alloc(SizeOf(TResource));
        Move(Res, P^, SizeOf(P^));
        SV_AddToResourceList(P^, C.UploadList);
        Inc(J);
       end;
 end;

if (J > 0) and (sv_allowupload.Value <> 0) then
 begin
  DPrint(['Verifying and uploading resources for "', PLChar(@C.NetName), '".']);

  Size := SV_SizeOfResourceList(C.UploadList, Pack);
  if Size = 0 then
   DPrint(['No resources for "', PLChar(@C.NetName), '".'])
  else
   begin
    DPrint(['"', PLChar(@C.NetName), '" requested upload of ', J, ' resources with total size = ', RoundTo(Size / 1024, -3), ' KB, including:']);
    if Pack[RT_MODEL] > 0 then
     DPrint([' -> Models: ', RoundTo(Pack[RT_MODEL] / 1024, -3), ' KB.']);
    if Pack[RT_SOUND] > 0 then
     DPrint([' -> Sounds: ', RoundTo(Pack[RT_SOUND] / 1024, -3), ' KB.']);
    if Pack[RT_DECAL] > 0 then
     DPrint([' -> Decals: ', RoundTo(Pack[RT_DECAL] / 1024, -3), ' KB.']);
    if Pack[RT_SKIN] > 0 then
     DPrint([' -> Skins: ', RoundTo(Pack[RT_SKIN] / 1024, -3), ' KB.']);
    if Pack[RT_GENERIC] > 0 then
     DPrint([' -> Generic: ', RoundTo(Pack[RT_GENERIC] / 1024, -3), ' KB.']);
    if Pack[RT_EVENTSCRIPT] > 0 then
     DPrint([' -> Event scripts: ', RoundTo(Pack[RT_EVENTSCRIPT] / 1024, -3), ' KB.']);
    
    EstSize := SV_EstimateNeededResources(C);
    if EstSize > sv_uploadmax.Value * (1024 * 1024) then
     begin
      DPrint(['The total resource size is too big, ignoring the request.']);
      SV_ClearResourceLists(C);
     end
    else
     begin
      if EstSize >= 1024 then
       DPrint(['Resources to request: ', RoundTo(EstSize / 1024, -3), ' KB.'])
      else
       DPrint(['Resources to request: ', EstSize, ' bytes.']);

      C.HasMissingResources := True;
      C.UploadComplete := False;
      SV_BatchUploadRequest(C);
      Exit;
     end;
   end;
 end;

C.HasMissingResources := False;
C.UploadComplete := True;
end;

procedure SV_ParseConsistencyResponse(var C: TClient);
var
 Failed: Boolean;
 FailedRes: array[0..MAX_RESOURCES - 1] of Boolean;
 Res: PResource;
 InMinS, InMaxS: TVec3;
 Reserved, NoReserved: array[1..32] of Byte;
 P: PPackedConsistency;
 I, Size, InResNum, NumConsistency: UInt;
 Buf: array[1..512] of LChar;
begin
Size := MSG_ReadShort;
if MSG_ReadCount + Size > MAX_NETBUFLEN then // buffer overrun prevention
 begin
  SV_DropClient(C, False, 'Bad consistency response.');
  Exit;
 end;

MemSet(NoReserved, SizeOf(NoReserved), 0);
MemSet(FailedRes, SizeOf(FailedRes), 0);
Failed := False;
NumConsistency := 0;

TEncode.UnMunge1(Pointer(UInt(gNetMessage.Data) + MSG_ReadCount), Size, SVS.SpawnCount);
MSG_StartBitReading(gNetMessage);
repeat
 if MSG_ReadBits(1) = 0 then
  Break;

 InResNum := MSG_ReadBits(12);
 if InResNum >= SV.NumResources then
  Failed := True
 else
  begin
   Res := @SV.Resources[InResNum];
   if not (RES_CHECKFILE in Res.Flags) then
    Failed := True
   else
    if CompareMem(@Res.Reserved, @NoReserved, SizeOf(NoReserved)) then
     if MSG_ReadBits(32) <> PUInt32(@Res.MD5Hash)^ then
      FailedRes[InResNum] := True
     else
    else
     begin
      MSG_ReadBitData(@InMinS, SizeOf(InMinS));
      MSG_ReadBitData(@InMaxS, SizeOf(InMaxS));
      Move(Res.Reserved, Reserved, SizeOf(Reserved));
      TEncode.UnMunge1(@Reserved, SizeOf(Reserved), SVS.SpawnCount);
      P := @Reserved;

      case TForceType(P.ForceType) of
       ftModelSameBounds:
        if not VectorCompare(P.MinS, InMinS) or not VectorCompare(P.MaxS, InMaxS) then
         FailedRes[InResNum] := True;

       ftModelSpecifyBounds:
        for I := 0 to 2 do
         if (InMinS[I] < P.MinS[I]) or (InMaxS[I] > P.MaxS[I]) then
          begin
           FailedRes[InResNum] := True;
           Break;
          end;

       ftModelSpecifyBoundsIfAvail:
        if (InMinS[0] <> -1) or (InMinS[1] <> -1) or (InMinS[2] <> -1) or (InMaxS[0] <> -1) or (InMaxS[1] <> -1) or (InMaxS[2] <> -1) then
         for I := 0 to 2 do
          if (InMinS[I] < P.MinS[I]) or (InMaxS[I] > P.MaxS[I]) then
           begin
            FailedRes[InResNum] := True;
            Break;
           end;

       else
        Failed := True;
      end;
     end;
  end;

 if MSG_BadRead then
  Failed := True
 else
  if not Failed then
   Inc(NumConsistency);

until Failed;

MSG_EndBitReading(gNetMessage);
if Failed or (NumConsistency <> SV.NumConsistency) then
 SV_DropClient(C, False, 'Bad file data in consistency response.')
else
 begin
  for I := 0 to SV.NumResources - 1 do
   if FailedRes[I] then
    begin
     Buf[Low(Buf)] := #0;
     if (C.Entity <> nil) and (DLLFunctions.InconsistentFile(C.Entity^, @SV.Resources[I].Name, @Buf) <> 0) then
      begin
       if Buf[Low(Buf)] > #0 then
        begin
         SV_ClientPrint(C, @Buf, False);
         SV_DropClient(C, False, @Buf);
        end
       else
        SV_DropClient(C, False, 'Bad file.');
       Exit;
      end;
    end;

  C.NeedConsistency := False;
 end;
end;

function SV_FileInConsistencyList(Name: PLChar; out C: PConsistency): Boolean;
var
 I: Int;
 P: PConsistency;
begin
for I := 0 to MAX_CONSISTENCY - 1 do
 begin
  P := @SV.PrecachedConsistency[I];
  if P.Name = nil then
   Break
  else
   if StrIComp(Name, P.Name) = 0 then
    begin
     C := P;
     Result := True;
     Exit;
    end;
 end;

Result := False;
end;

procedure SV_TransferConsistencyInfo;
var
 Num: UInt;
 I: Int;
 Res: PResource;
 C: PConsistency;
 Buf: array[1..MAX_PATH_A] of LChar;
 Hash: TMD5Hash;
 P: PPackedConsistency;
 MinS, MaxS: TVec3;
begin
Num := 0;

for I := 0 to SV.NumResources - 1 do
 begin
  Res := @SV.Resources[I];
  if not (RES_CHECKFILE in Res.Flags) and SV_FileInConsistencyList(@Res.Name, C) then
   begin
    if Res.ResourceType = RT_SOUND then
     StrCopy(StrECopy(@Buf, 'sound' + CorrectSlash), @Res.Name)
    else
     StrCopy(@Buf, @Res.Name);

    if MD5_Hash_File(Hash, @Buf, True, False, nil) then
     begin
      Move(Hash, Res.MD5Hash, SizeOf(Res.MD5Hash));
      if Res.ResourceType = RT_MODEL then
       begin
        P := @Res.Reserved;                             
        case C.ForceType of
         ftModelSameBounds:
          begin
           if not R_GetStudioBounds(@Buf, MinS, MaxS) then
            begin
             Print(['Warning: Unable to get bounds for "', PLChar(@Buf), '".']);
             Continue;
            end;

           P.ForceType := Byte(C.ForceType);
           P.MinS := MinS;
           P.MaxS := MaxS;
           TEncode.Munge1(@Res.Reserved, SizeOf(Res.Reserved), SVS.SpawnCount);
          end;

         ftModelSpecifyBounds, ftModelSpecifyBoundsIfAvail:
          begin
           P.ForceType := Byte(C.ForceType);
           P.MinS := C.MinS;
           P.MaxS := C.MaxS;
           TEncode.Munge1(@Res.Reserved, SizeOf(Res.Reserved), SVS.SpawnCount);
          end;
        end;
       end;

      Include(Res.Flags, RES_CHECKFILE);
      Inc(Num);
     end;
   end;
 end;

SV.NumConsistency := Num;
end;

procedure SV_CheckDownloadCVars;
begin
if (sv_allowdownload.Value <> 0) and (sv_allowdownload.Value <> 1) then
 CVar_DirectSet(sv_allowdownload, '1');
if (sv_send_resources.Value <> 0) and (sv_send_resources.Value <> 1) then
 CVar_DirectSet(sv_send_resources, '1');
if (sv_send_logos.Value <> 0) and (sv_send_logos.Value <> 1) then
 CVar_DirectSet(sv_send_logos, '1');
end;

procedure SV_BeginFileDownload_F; cdecl;
var
 S: PLChar;
 Res: TResource;
 Hash: TMD5Hash;
 Buffer: Pointer;
 Size: UInt32;
begin
if (CmdSource = csClient) and (Cmd_Argc = 2) then
 begin
  S := Cmd_Argv(1);
  if S^ > #0 then
   begin
    SV_CheckDownloadCVars;

    if (sv_allowdownload.Value <> 0) and IsSafeFile(S) then
     if StrLComp(S, '!MD5', 4) = 0 then
      if (sv_send_logos.Value <> 0) and MD5_IsValid(PLChar(UInt(S) + 4)) then
       begin
        MemSet(Res, SizeOf(Res), 0);
        Buffer := nil;
        Size := 0;
        COM_HexConvert(PLChar(UInt(S) + 4), 32, @Hash);
        if HPAK_ResourceForHash('custom.hpk', @Hash, @Res) and
           HPAK_GetDataPointer('custom.hpk', Res, @Buffer, @Size) and (Buffer <> nil) and (Size > 0) then
         begin
          HostClient.Netchan.CreateFileFragmentsFromBuffer(S, Buffer, Size);
          HostClient.Netchan.FragSend;
          Mem_Free(Buffer);
          Exit;
         end;

        if Buffer <> nil then
         Mem_Free(Buffer);
       end
      else
     else
      if (sv_send_resources.Value <> 0) and HostClient.Netchan.CreateFileFragments(S) then
       begin
        HostClient.Netchan.FragSend;
        Exit;
       end;

    HostClient.Netchan.NetMessage.Write<UInt8>(SVC_FILETXFERFAILED);
    HostClient.Netchan.NetMessage.WriteString(S);
   end;
 end;
end;

procedure SV_AddResource(ResType: TResourceType; FileName: PLChar; DownloadSize: UInt; Flags: TResourceFlags; Index: UInt);
var
 P: PResource;
begin
if SV.NumResources >= MAX_RESOURCES then
 Sys_Error('SV_AddResource: Too many resources on server.');

P := @SV.Resources[SV.NumResources];
Inc(SV.NumResources);

P.ResourceType := ResType;
StrLCopy(@P.Name, FileName, SizeOf(P.Name) - 1);
P.DownloadSize := DownloadSize;
P.Flags := Flags;
P.Index := Index;
end;

procedure SV_CreateResourceList;
var
 I: Int;
 S: PLChar;
 Buf: array[1..MAX_PATH_A * 2] of LChar;
 B: Boolean;
 P: PPrecachedEvent;
begin
SV.NumResources := 0;
for I := 1 to MAX_GENERICS - 1 do
 begin
  S := SV.PrecachedGeneric[I];
  if S = nil then
   Break
  else
   if SVS.MaxClients > 1 then
    SV_AddResource(RT_GENERIC, S, FS_SizeByName(S), [], I)
   else
    SV_AddResource(RT_GENERIC, S, 0, [], I);
 end;

B := False;
for I := 1 to MAX_SOUNDS - 1 do
 begin
  S := SV.PrecachedSoundNames[I];
  if S = nil then
   Break
  else
   if (S^ = '!') and not B then
    begin
     B := True;
     SV_AddResource(RT_SOUND, '!', 0, [RES_FATALIFMISSING], I);
    end
   else
    if SVS.MaxClients > 1 then
     begin
      StrCopy(StrECopy(@Buf, 'sound' + CorrectSlash), S);
      SV_AddResource(RT_SOUND, S, FS_SizeByName(@Buf), [], I)
     end
    else
     SV_AddResource(RT_SOUND, S, 0, [], I);
 end;

for I := 1 to MAX_MODELS - 1 do
 begin
  S := SV.PrecachedModelNames[I];
  if S = nil then
   Break
  else
   if SVS.MaxClients > 1 then
    if S^ = '*' then
     SV_AddResource(RT_MODEL, S, 0, SV.PrecachedModelFlags[I], I)
    else
     SV_AddResource(RT_MODEL, S, FS_SizeByName(S), SV.PrecachedModelFlags[I], I)
   else
    SV_AddResource(RT_MODEL, S, 0, SV.PrecachedModelFlags[I], I);
 end;

for I := 0 to SVDecalNameCount - 1 do
 SV_AddResource(RT_DECAL, @SVDecalNames[I], Draw_DecalSize(I), [], I);

for I := 1 to MAX_EVENTS - 1 do
 begin
  P := @SV.PrecachedEvents[I];
  if P.Data = nil then
   Break
  else
   SV_AddResource(RT_EVENTSCRIPT, P.Name, P.Size, [RES_FATALIFMISSING], I);
 end;
end;

procedure SV_CreateGenericResources;
var
 Buf: array[1..MAX_MAP_NAME] of LChar;
 P, P2: Pointer;
 S: PLChar;
 I: UInt;
begin
COM_StripExtension(@SV.MapFileName, @Buf);
COM_DefaultExtension(@Buf, '.res');
COM_FixSlashes(@Buf);

P := COM_LoadFile(@Buf, FILE_ALLOC_MEMORY, nil);
if P <> nil then
 begin
  P2 := P;

  DPrint([sLineBreak + 'Precaching from resource file "', PLChar(@Buf), '".' + sLineBreak +
          '----------------------------------']);
  SV.NumResGeneric := 0;
  I := 0;

  while True do
   begin
    P := COM_Parse(P);
    if (P = nil) or (COM_Token[Low(COM_Token)] = #0) then
     Break
    else
     begin
      Inc(I);
      COM_FixSlashes(@COM_Token);
      if not IsSafeFile(@COM_Token) then
       DPrint(['  ', PLChar(@COM_Token), ': cannot be precached'])
      else
       if not FS_FileExists(@COM_Token) then
        DPrint(['  ', PLChar(@COM_Token), ': missing from the server'])
       else
        begin
         S := @SV.PrecachedResGeneric[SV.NumResGeneric];
         StrLCopy(S, @COM_Token, SizeOf(SV.PrecachedResGeneric[0]) - 1);
         PF_PrecacheGeneric(S);
         DPrint(['  ', S]);
         Inc(SV.NumResGeneric);
        end;
     end;
   end;

  DPrint(['----------------------------------' + sLineBreak,
          'Total: ', SV.NumResGeneric, ' resources out of ', I, '.' + sLineBreak]);
  COM_FreeFile(P2);
 end
else
 DPrint(['Resource file "', PLChar(@Buf), '" is missing, no additional resources would be precached.']);
end;

procedure SV_ProcessFile(var C: TClient; Name: PLChar);
var
 MD5Hash: TMD5Hash;
 P, P2: PResource;
 Cust: PCustomization;
 LumpCount: UInt;
begin
if Name = nil then
 Print('SV_ProcessFile: Bad name pointer.')
else
 if Name^ <> '!' then
  Print(['SV_ProcessFile: Non-customization file upload of "', Name, '".'])
 else
  if (StrLComp(Name, '!MD5', 4) <> 0) or not MD5_IsValid(PLChar(UInt(Name) + 4)) then
   Print('SV_ProcessFile: Bad customization hash.')
  else
   begin
    COM_HexConvert(PLChar(UInt(Name) + 4), 32, @MD5Hash);
    P := C.UploadList.Next;
    while P <> @C.UploadList do
     begin
      P2 := P.Next;
      if CompareMem(@P.MD5Hash, @MD5Hash, SizeOf(MD5Hash)) then
       begin
        if P.DownloadSize <> C.Netchan.TempBufferSize then
         Print(['SV_ProcessFile: Downloaded ', C.Netchan.TempBufferSize, ' bytes for ', P.DownloadSize, ' byte file (size mismatch) on "', PLChar(@C.NetName), '".'])
        else
         if IsResourceInCustom(@C.Customization, @P.MD5Hash) then
          DPrint('Duplicate resource received and ignored.')
         else
          begin
           HPAK_AddLump(True, 'custom.hpk', P, C.Netchan.TempBuffer, nil);
           Exclude(P.Flags, RES_WASMISSING);
           SV_MoveToOnHandList(C, P^);
           if not SV_CreateCustomization(C.Customization, P^, -1, [FCUST_FROMHPAK, FCUST_WIPEDATA, FCUST_IGNOREINIT], Cust, LumpCount) then
            Print(['Error parsing custom decal from "', PLChar(@C.NetName), '".']);
           Exit;
          end;

        SV_RemoveFromResourceList(P^);
        Mem_Free(P);
        Exit;
       end;

      P := P2;
     end;
    
    Print('SV_ProcessFile: Unrequested resource.');
   end;
end;

end.
