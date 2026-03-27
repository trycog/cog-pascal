unit workspace;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function FindProjectRoot(const FilePath: string): string;
function DiscoverProjectName(const ProjectRoot: string): string;
function MakeRelativePath(const FilePath, ProjectRoot: string): string;

implementation

function FindProjectRoot(const FilePath: string): string;
var
  Dir: string;
begin
  if DirectoryExists(FilePath) then
    Dir := FilePath
  else
    Dir := ExtractFileDir(FilePath);

  Dir := ExpandFileName(Dir);

  while Dir <> '' do
  begin
    { Check for Lazarus project file }
    if FileExists(Dir + DirectorySeparator + '*.lpr') or
       FileExists(Dir + DirectorySeparator + '*.lpi') then
    begin
      Result := Dir;
      Exit;
    end;

    { Check for Delphi project file }
    if FileExists(Dir + DirectorySeparator + '*.dpr') or
       FileExists(Dir + DirectorySeparator + '*.dproj') then
    begin
      Result := Dir;
      Exit;
    end;

    { Check for package file }
    if FileExists(Dir + DirectorySeparator + '*.dpk') or
       FileExists(Dir + DirectorySeparator + '*.lpk') then
    begin
      Result := Dir;
      Exit;
    end;

    { Move up one directory }
    if Dir = ExtractFileDir(Dir) then
      Break;
    Dir := ExtractFileDir(Dir);
  end;

  { Fallback: use the file's directory }
  if DirectoryExists(FilePath) then
    Result := FilePath
  else
    Result := ExtractFileDir(FilePath);
end;

function SearchForProjectFile(const Dir, Pattern: string): string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FindFirst(Dir + DirectorySeparator + Pattern, faAnyFile, SR) = 0 then
  begin
    Result := Dir + DirectorySeparator + SR.Name;
    FindClose(SR);
  end;
end;

function DiscoverProjectName(const ProjectRoot: string): string;
var
  ProjectFile: string;
begin
  { Try to find a project file and extract the name }
  ProjectFile := SearchForProjectFile(ProjectRoot, '*.lpr');
  if ProjectFile = '' then
    ProjectFile := SearchForProjectFile(ProjectRoot, '*.dpr');
  if ProjectFile = '' then
    ProjectFile := SearchForProjectFile(ProjectRoot, '*.lpi');
  if ProjectFile = '' then
    ProjectFile := SearchForProjectFile(ProjectRoot, '*.dproj');
  if ProjectFile = '' then
    ProjectFile := SearchForProjectFile(ProjectRoot, '*.lpk');
  if ProjectFile = '' then
    ProjectFile := SearchForProjectFile(ProjectRoot, '*.dpk');

  if ProjectFile <> '' then
    Result := ChangeFileExt(ExtractFileName(ProjectFile), '')
  else
    Result := ExtractFileName(ProjectRoot);
end;

function MakeRelativePath(const FilePath, ProjectRoot: string): string;
var
  FullFile, FullRoot: string;
begin
  FullFile := ExpandFileName(FilePath);
  FullRoot := IncludeTrailingPathDelimiter(ExpandFileName(ProjectRoot));

  if Pos(FullRoot, FullFile) = 1 then
    Result := Copy(FullFile, Length(FullRoot) + 1, MaxInt)
  else
    Result := FullFile;
end;

end.
