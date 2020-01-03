unit GameLib;

interface

uses SysUtils, Default, SDK;

function GetDispatch(Name: PLChar): Pointer;
procedure Host_InitializeGameDLL;
procedure ReleaseEntityDLLs;

const
 MAX_EXTDLL = 50;
 
var
 NumExtDLL: UInt;
 ExtDLL: array[0..MAX_EXTDLL - 1] of TExtLibData;

 ModInfo: TModInfo;
 DLLFunctions: TDLLFunctions;
 NewDLLFunctions: TNewDLLFunctions;

 FakeSwdsFuncs: PEngineFuncs;
 FakeSwdsHandle: THandle = INVALID_HANDLE_VALUE;

implementation

uses Common, Console, Delta, Edict, FileSys, Host, Memory,
  Network, ParseLib, Renderer, SVEdict, SVExport, SVDelta, SVMain, SVMove,
  SysArgs, SysMain;

var
 SkipParseLib: Boolean;

procedure SV_ResetModInfo;
begin
MemSet(ModInfo, SizeOf(ModInfo), 0);
ModInfo.Version := 1;
ModInfo.SVOnly := True;
end;

procedure DLL_SetModKey(out Info: TModInfo; Key, Value: PLChar);
var
 I: Boolean;
begin
I := Info.CustomGame;
Info.CustomGame := True;
if StrComp(Key, 'url_info') = 0 then
 StrLCopy(@Info.URLInfo, Value, SizeOf(Info.URLInfo) - 1)
else
 if StrComp(Key, 'url_dl') = 0 then
  StrLCopy(@Info.URLDownload, Value, SizeOf(Info.URLDownload) - 1)
 else
  if StrComp(Key, 'version') = 0 then
   Info.Version := StrToInt(Value)
  else
   if StrComp(Key, 'size') = 0 then
    Info.Size := StrToInt(Value)
   else
    if StrComp(Key, 'svonly') = 0 then
     Info.SVOnly := StrToInt(Value) <> 0
    else
     if StrComp(Key, 'cldll') = 0 then
      Info.ClientDLL := StrToInt(Value) <> 0
     else
      if StrComp(Key, 'secure') = 0 then
       Info.Secure := StrToInt(Value) <> 0
      else
       begin
        Info.CustomGame := I;
        if StrComp(Key, 'hlversion') = 0 then
         StrLCopy(@Info.HLVersion, Value, SizeOf(Info.HLVersion) - 1)
        else
         if StrComp(Key, 'type') = 0 then
          if StrIComp(Value, 'singleplayer') = 0 then
           Info.GameType := gtSingleplayer
          else
           if StrIComp(Value, 'multiplayer') = 0 then
            Info.GameType := gtMultiplayer
           else
            Info.GameType := gtUnknown
         else
          if StrComp(Key, 'fallback_dir') = 0 then
           COM_AddDefaultDir(Value);           
       end;
end;

procedure LoadThisDLL(Name: PLChar);
var
 H: THandle;
 F: procedure(Engine: PEngineFuncs; GlobalVars: PGlobalVars); stdcall;
begin
FS_GetLocalCopy(Name);
H := Sys_LoadModule(Name);
if H <> INVALID_HANDLE_VALUE then
 begin
  F := Sys_GetProcAddress(H, 'GiveFnptrsToDll');
  if @F = nil then
   Print(['LoadThisDLL: Couldn''t get GiveFnptrsToDll in "', Name, '".']) 
  else
   begin
    if FakeSwdsFuncs <> nil then               
     F(FakeSwdsFuncs, @GlobalVars)
    else
     F(@EngFuncs, @GlobalVars);

    if NumExtDLL = MAX_EXTDLL then
     Print('LoadThisDLL: Too many DLLs, ignoring remainder.')
    else
     begin
      MemSet(ExtDLL[NumExtDLL], SizeOf(ExtDLL[NumExtDLL]), 0);
      ExtDLL[NumExtDLL].Handle := H;
      {$IFDEF MSWINDOWS}
      if not SkipParseLib then
       WriteExportTable(ExtDLL[NumExtDLL], Pointer(H));
      {$ENDIF}
      Inc(NumExtDLL);
      Exit;
     end;
   end;

  Sys_UnloadModule(H);
 end
else
 Print(['LoadThisDLL: Couldn''t load "', Name, '": error ', Sys_LastModuleErr, '.']);
end;

function GetDispatch(Name: PLChar): Pointer;
var
 I: Int;
begin
for I := 0 to NumExtDLL - 1 do
 begin
  Result := Sys_GetProcAddress(ExtDLL[I].Handle, Name);
  if Result <> nil then
   Exit;
 end;

Result := nil;
end;

procedure LoadEntityDLLs;
var
 F: TFile;
 FileSize: Int64;
 P, P2: Pointer;
 Key: array[0..63] of LChar;
 Value: array[0..255] of LChar;
 ExtBuf: array[0..31] of LChar;
 S: PLChar;
 {$IFNDEF MSWINDOWS}S2: PLChar;{$ENDIF}
 NameBuf, FullNameBuf: array[0..MAX_PATH_W - 1] of LChar;
 GetEntityAPI: function(var FunctionTable: TDLLFunctions; InterfaceVersion: Int32): Int32; cdecl;
 GetEntityAPI2: function(var FunctionTable: TDLLFunctions; var InterfaceVersion: Int32): Int32; cdecl;
 GetNewDLLFunctions: function(var FunctionTable: TNewDLLFunctions; var InterfaceVersion: Int32): Int32; cdecl;
 Version: Int32;
begin
SV_ResetModInfo;
NumExtDLL := 0;
MemSet(ExtDLL, SizeOf(ExtDLL), 0);
if StrIComp(GameDir, DEFAULT_GAME) <> 0 then
 ModInfo.CustomGame := True;

FullNameBuf[0] := #0;
if FS_Open(F, 'liblist.gam', 'r') then
 begin
  FileSize := FS_Size(F);
  if FileSize = 0 then
   Sys_Error('LoadEntityDLLs: liblist.gam is empty.');

  P := Mem_Alloc(FileSize + 1);
  if P = nil then
   Sys_Error(['LoadEntityDLLs: liblist.gam is too big, out of memory.']);

  if FS_Read(F, P, FileSize) < FileSize then
   Sys_Error('LoadEntityDLLs: File read error.');
   
  PLChar(UInt(P) + FileSize)^ := #0;
  COM_IgnoreColons := True;
  P2 := P;
  while True do
   begin
    P := COM_Parse(P);
    if COM_Token[Low(COM_Token)] = #0 then
     Break;
    StrLCopy(Key, @COM_Token[1], SizeOf(Key) - 1);
    P := COM_Parse(P);
    StrLCopy(Value, @COM_Token[1], SizeOf(Value) - 1);

    if StrIComp(Key, {$IFDEF MSWINDOWS}'gamedll'{$ELSE}'gamedll_linux'{$ENDIF}) <> 0 then
     DLL_SetModKey(ModInfo, Key, Value)
    else
     begin
      S := COM_ParmValueByName('-dll');
      if (S = nil) or (S^ = #0) then
       S := StrLCopy(NameBuf, Value, SizeOf(NameBuf) - 1)
      else
       S := StrLCopy(NameBuf, S, SizeOf(NameBuf) - 1);

      COM_FixSlashes(NameBuf);

      {$IFNDEF MSWINDOWS}
      S2 := StrScan(S, '_');
      if S2 <> nil then
       begin
        S2 := #0;
        StrCat(S, '_i386.so');
       end;
      {$ENDIF}

      {$IFDEF MSWINDOWS}
       StrFmt(FullNameBuf, '%s\%s\%s', [BaseDir, GameDir, S]);
       COM_FileExtension(FullNameBuf, ExtBuf, SizeOf(ExtBuf));
       if StrIComp(ExtBuf, 'dll') = 0 then
        begin
         DPrint(['Adding DLL: ', GameDir, '\', S, '.']);
         LoadThisDLL(FullNameBuf);
        end
       else
        DPrint(['Skipping non-dll: ', FullNameBuf, '.']);
      {$ELSE}
       StrFmt(FullNameBuf, '%s/%s/%s', [BaseDir, GameDir, S]);
       COM_FileExtension(FullNameBuf, ExtBuf, SizeOf(ExtBuf));
       if StrIComp(ExtBuf, 'so') = 0 then
        begin
         DPrint(['Adding shared library: ', GameDir, '/', S, '.']);
         LoadThisDLL(FullNameBuf);
        end
       else
        DPrint(['Skipping non-shared library: ', FullNameBuf, '.']);
      {$ENDIF}
     end;
   end;

  COM_IgnoreColons := False;
  Mem_Free(P2);
  FS_Close(F);
 end
else
 begin
  S := Sys_FindFirst(DEFAULT_GAME + {$IFDEF MSWINDOWS}'\dlls\*.dll'{$ELSE}'/dlls/*.so'{$ENDIF}, nil);
  while (S <> nil) and (S^ > #0) do
   begin
    {$IFDEF MSWINDOWS}
     StrFmt(FullNameBuf, '%s\%s\%s', [BaseDir, DEFAULT_GAME + '\dlls', S]);
    {$ELSE}
     StrFmt(FullNameBuf, '%s/%s/%s', [BaseDir, DEFAULT_GAME + '/dlls', S]);
    {$ENDIF}
    LoadThisDLL(@FullNameBuf);
    S := Sys_FindNext(nil);
   end;
  Sys_FindClose;   
 end;

if (FullNameBuf[0] = #0) or (NumExtDLL = 0) then
 begin
  THost.Error('No game DLL provided to the engine, exiting.');
  Exit;
 end;

MemSet(NewDLLFunctions, SizeOf(NewDLLFunctions), 0);
GetNewDLLFunctions := GetDispatch('GetNewDLLFunctions');
if @GetNewDLLFunctions <> nil then
 begin
  Version := NEWDLL_INTERFACE_VERSION;
  GetNewDLLFunctions(NewDLLFunctions, Version);
 end;

GetEntityAPI2 := GetDispatch('GetEntityAPI2');
if @GetEntityAPI2 <> nil then
 begin
  Version := DLL_INTERFACE_VERSION;
  if GetEntityAPI2(DLLFunctions, Version) = 0 then
   begin
    Print(['==================' + sLineBreak + 'Game DLL version mismatch.' + sLineBreak +
           'DLL version is ', Version, ', engine version is ', DLL_INTERFACE_VERSION, '.']);
    if Version <= DLL_INTERFACE_VERSION then
     Print(['The game DLL for ', GameDir, ' appears to be outdated, check for updates.'])
    else
     Print('Engine appears to be outdated, check for updates.');
    Print('==================');
    THost.Error('Game DLL version mismatch.');
    Exit;
   end;
 end
else
 begin
  GetEntityAPI := GetDispatch('GetEntityAPI');
  if @GetEntityAPI = nil then
   begin
    THost.Error(['Couldn''t get DLL API from ', FullNameBuf, '.']);
    Exit;
   end;
  Version := DLL_INTERFACE_VERSION;
  if GetEntityAPI(DLLFunctions, Version) = 0 then
   begin
    Print(['==================' + sLineBreak + 'Game DLL version mismatch.']);
    Print(['The game DLL for ', GameDir, ' appears to be outdated, check for updates.']);
    Print('==================');
    THost.Error('Game DLL version mismatch.');
    Exit;
   end;
 end;

if ModInfo.CustomGame then
 DPrint(['DLL loaded for mod ', DLLFunctions.GetGameDescription, '.'])
else
 DPrint(['DLL loaded for game ', DLLFunctions.GetGameDescription, '.']);
end;

function LoadFakeSwds(Name: PLChar): Boolean;
var
 H: THandle;
 F: function(const E: TEngineFuncs; Size: UInt): PEngineFuncs;
begin
Result := False;

FS_GetLocalCopy(Name);
H := Sys_LoadModule(Name);
if H <> INVALID_HANDLE_VALUE then
 begin
  F := Sys_GetProcAddress(H, 'SwitchEngineToFakeSwds');
  if @F <> nil then
   begin
    FakeSwdsFuncs := F(EngFuncs, SizeOf(EngFuncs));
    if FakeSwdsFuncs <> nil then
     begin
      DPrint('Fake SWDS module loaded.');
      FakeSwdsHandle := H;
      Result := True;
      Exit;
     end;
   end;

  Sys_UnloadModule(H);
 end;
end;

procedure ReleaseFakeSwds;
var
 F: procedure;
begin
if (FakeSwdsHandle <> INVALID_HANDLE_VALUE) and (FakeSwdsFuncs <> nil) then
 begin
  F := Sys_GetProcAddress(FakeSwdsHandle, 'DestroyFakeSwds');
  if @F <> nil then
   begin
    F;
    Sys_UnloadModule(FakeSwdsHandle);
    FakeSwdsFuncs := nil;
    FakeSwdsHandle := INVALID_HANDLE_VALUE;
   end;
 end;
end;

procedure SV_CheckBlendingInterface;
var
 I: Int;
 F: function(Version: Int32; var PInterface: PSVBlendingInterface; var PStudio: TEngineStudioAPI; RotationMatrix, BoneTransform: Pointer): Int32; cdecl;
begin
R_ResetSVBlending;
for I := 0 to NumExtDLL - 1 do
 begin
  F := Sys_GetProcAddress(ExtDLL[I].Handle, 'Server_GetBlendingInterface');
  if @F <> nil then
   if F(SV_BLENDING_INTERFACE_VERSION, SVBlendingAPI, ServerStudioAPI, @RotationMatrix, @BoneTransform) <> 0 then
    Break
   else
    begin
     DPrint('Couldn''t get studio model blending interface from game library. Version mismatch?');
     R_ResetSVBlending; 
    end;
 end;
end;

procedure SV_CheckSaveGameCommentInterface;
var
 I: Int;
 F: Pointer;
begin
for I := 0 to NumExtDLL - 1 do
 begin
  F := Sys_GetProcAddress(ExtDLL[I].Handle, 'SV_SaveGameComment');
  if F <> nil then
   begin
    Exit;
   end;
 end;
end;

procedure Host_InitializeGameDLL;
begin
CBuf_Execute;

if not SVS.InitGameDLL then
 begin
  // SkipParseLib := COM_CheckParm('-skipparselib') > 0;
  SkipParseLib := True;
  SVS.InitGameDLL := True;

  if not LoadFakeSwds({$IFDEF MSWINDOWS}'swds.dll'{$ELSE}'swds.so'{$ENDIF}) then
   LoadFakeSwds({$IFDEF MSWINDOWS}'fake_swds\swds.dll'{$ELSE}'fake_swds\swds.so'{$ENDIF});

  LoadEntityDLLs;
  DLLFunctions.GameInit;
  DLLFunctions.PM_Init(ServerMove);
  DLLFunctions.RegisterEncoders;
  Delta_InitEncoders;
  SV_GetPlayerHulls;
  SV_CheckBlendingInterface;
  SV_CheckSaveGameCommentInterface;
  CBuf_Execute;
 end;
end;

procedure ReleaseEntityDLLs;
var
 I: Int;
 P: PExtLibData;
begin
if SVS.InitGameDLL then
 begin
  FreeAllEntPrivateData;
  if @NewDLLFunctions.GameShutdown <> nil then
   NewDLLFunctions.GameShutdown;

  CVar_UnlinkExternals;
  for I := 0 to NumExtDLL - 1 do
   begin
    P := @ExtDLL[I];
    Sys_UnloadModule(P.Handle);
    if P.ExportTable <> nil then
     Mem_Free(P.ExportTable);
    MemSet(P^, SizeOf(P^), 0);
   end;

  ReleaseFakeSwds;

  SVS.InitGameDLL := False;
 end;
end;

end.
