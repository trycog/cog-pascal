program cogpascal;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, scip, symbols, analyzer, forms, workspace;

var
  OutputPath: string;
  FilePaths: TStringList;
  I: Integer;
  ProjectRoot: string;
  PackageName: string;
  Source: string;
  RelPath: string;
  Ext: string;
  Doc: TScipDocument;
  Idx: TScipIndex;
  DocIdx: Integer;
  PascalAnalyzer: TPascalAnalyzer;
  ProgressJson: string;
  F: TStringList;
begin
  FilePaths := TStringList.Create;
  try
    { Parse arguments: --output <path> <file> [<file> ...] }
    I := 1;
    while I <= ParamCount do
    begin
      if ParamStr(I) = '--output' then
      begin
        Inc(I);
        if I <= ParamCount then
          OutputPath := ParamStr(I);
      end
      else
        FilePaths.Add(ParamStr(I));
      Inc(I);
    end;

    if OutputPath = '' then
    begin
      WriteLn(StdErr, 'Error: --output <path> is required');
      Halt(1);
    end;

    if FilePaths.Count = 0 then
    begin
      WriteLn(StdErr, 'Error: no input files');
      Halt(1);
    end;

    { Discover project root from first file }
    ProjectRoot := FindProjectRoot(FilePaths[0]);
    PackageName := DiscoverProjectName(ProjectRoot);

    { Initialize index }
    Idx.Metadata.Version := 0;
    Idx.Metadata.ToolInfo.Name := 'cog-pascal';
    Idx.Metadata.ToolInfo.Version := '0.1.0';
    Idx.Metadata.ToolInfo.Arguments := TStringList.Create;
    for I := 1 to ParamCount do
      Idx.Metadata.ToolInfo.Arguments.Add(ParamStr(I));
    Idx.Metadata.ProjectRoot := 'file://' + ProjectRoot;
    Idx.Metadata.TextDocumentEncoding := 1; { UTF-8 }

    SetLength(Idx.Documents, 0);

    PascalAnalyzer := TPascalAnalyzer.Create;
    try
      for I := 0 to FilePaths.Count - 1 do
      begin
        try
          RelPath := MakeRelativePath(FilePaths[I], ProjectRoot);
          Ext := LowerCase(ExtractFileExt(FilePaths[I]));

          { Read file }
          F := TStringList.Create;
          try
            F.LoadFromFile(FilePaths[I]);
            Source := F.Text;
          finally
            F.Free;
          end;

          { Analyze based on file type }
          if (Ext = '.dfm') or (Ext = '.lfm') then
            Doc := AnalyzeFormFile(Source, PackageName, RelPath)
          else
            Doc := PascalAnalyzer.Analyze(Source, PackageName, RelPath);

          { Add document to index }
          DocIdx := Length(Idx.Documents);
          SetLength(Idx.Documents, DocIdx + 1);
          Idx.Documents[DocIdx] := Doc;

          { Report progress }
          ProgressJson := '{"type":"progress","event":"file_done","path":"' +
                          StringReplace(FilePaths[I], '\', '\\', [rfReplaceAll]) + '"}';
          WriteLn(StdErr, ProgressJson);
        except
          on E: Exception do
          begin
            ProgressJson := '{"type":"progress","event":"file_error","path":"' +
                            StringReplace(FilePaths[I], '\', '\\', [rfReplaceAll]) + '"}';
            WriteLn(StdErr, ProgressJson);
          end;
        end;
      end;
    finally
      PascalAnalyzer.Free;
    end;

    { Write SCIP index }
    WriteScipIndex(Idx, OutputPath);

    { Cleanup }
    Idx.Metadata.ToolInfo.Arguments.Free;

  finally
    FilePaths.Free;
  end;
end.
