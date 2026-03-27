unit forms;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, scip, symbols;

function AnalyzeFormFile(const Source, PackageName, RelativePath: string): TScipDocument;

implementation

type
  TFormParser = class
  private
    FSource: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    FPackageName: string;
    FRelativePath: string;
    FOccurrences: array of TScipOccurrence;
    FSymbols: array of TScipSymbolInfo;

    function Peek: Char;
    function AtEnd: Boolean;
    procedure Advance;
    procedure SkipWhitespace;
    function ReadToken: string;
    function ReadUntilEOL: string;
    procedure AddOccurrence(const Symbol: string; Roles: Integer; Range: TScipRange);
    procedure AddSymbol(const Symbol, DisplayName: string; Kind: Integer; const EnclosingSymbol: string);
    procedure ParseObject(const ParentSymbol: string);
  public
    constructor Create;
    function Parse(const Source, PackageName, RelativePath: string): TScipDocument;
  end;

constructor TFormParser.Create;
begin
  inherited Create;
end;

function TFormParser.Peek: Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TFormParser.AtEnd: Boolean;
begin
  Result := FPos > Length(FSource);
end;

procedure TFormParser.Advance;
begin
  if FPos <= Length(FSource) then
  begin
    if FSource[FPos] = #10 then
    begin
      Inc(FLine);
      FCol := 0;
    end
    else
      Inc(FCol);
    Inc(FPos);
  end;
end;

procedure TFormParser.SkipWhitespace;
begin
  while (not AtEnd) and (Peek in [' ', #9, #13, #10]) do
    Advance;
end;

function TFormParser.ReadToken: string;
var
  Start: Integer;
begin
  Result := '';
  SkipWhitespace;
  if AtEnd then Exit;

  if Peek in ['a'..'z', 'A'..'Z', '_'] then
  begin
    Start := FPos;
    while (not AtEnd) and (Peek in ['a'..'z', 'A'..'Z', '0'..'9', '_', '.']) do
      Advance;
    Result := Copy(FSource, Start, FPos - Start);
  end
  else if Peek = '''' then
  begin
    { Skip string literal }
    Advance;
    while not AtEnd do
    begin
      if Peek = '''' then
      begin
        Advance;
        if (not AtEnd) and (Peek = '''') then
          Advance
        else
          Break;
      end
      else
        Advance;
    end;
    Result := '';
  end
  else
  begin
    Result := Peek;
    Advance;
  end;
end;

function TFormParser.ReadUntilEOL: string;
var
  Start: Integer;
begin
  Start := FPos;
  while (not AtEnd) and not (Peek in [#13, #10]) do
    Advance;
  Result := Trim(Copy(FSource, Start, FPos - Start));
end;

procedure TFormParser.AddOccurrence(const Symbol: string; Roles: Integer; Range: TScipRange);
var
  Idx: Integer;
begin
  Idx := Length(FOccurrences);
  SetLength(FOccurrences, Idx + 1);
  FOccurrences[Idx].Symbol := Symbol;
  FOccurrences[Idx].SymbolRoles := Roles;
  FOccurrences[Idx].Range := Range;
  FOccurrences[Idx].HasEnclosingRange := False;
end;

procedure TFormParser.AddSymbol(const Symbol, DisplayName: string; Kind: Integer; const EnclosingSymbol: string);
var
  Idx: Integer;
begin
  Idx := Length(FSymbols);
  SetLength(FSymbols, Idx + 1);
  FSymbols[Idx].Symbol := Symbol;
  FSymbols[Idx].DisplayName := DisplayName;
  FSymbols[Idx].Kind := Kind;
  FSymbols[Idx].EnclosingSymbol := EnclosingSymbol;
  FSymbols[Idx].Documentation := nil;
end;

procedure TFormParser.ParseObject(const ParentSymbol: string);
var
  Token, CompName, CompClass, Sym: string;
  IdentLine, IdentCol: Integer;
  Range: TScipRange;
begin
  { Format: object ComponentName: TComponentClass }
  { or: inherited ComponentName: TComponentClass }
  { or: inline ComponentName: TComponentClass }
  SkipWhitespace;
  IdentLine := FLine;
  IdentCol := FCol;
  CompName := ReadToken;
  if CompName = '' then Exit;

  SkipWhitespace;
  Token := ReadToken; { should be ':' }
  if Token <> ':' then Exit;

  SkipWhitespace;
  CompClass := ReadToken;
  if CompClass = '' then Exit;

  Sym := MakeFormComponentSymbol(FPackageName, FRelativePath, CompName, CompClass);
  Range.StartLine := IdentLine;
  Range.StartCol := IdentCol;
  Range.EndLine := IdentLine;
  Range.EndCol := IdentCol + Length(CompName);
  AddOccurrence(Sym, ROLE_DEFINITION, Range);
  AddSymbol(Sym, CompName + ': ' + CompClass, KIND_FIELD, ParentSymbol);

  { Parse properties and nested objects until 'end' }
  while not AtEnd do
  begin
    SkipWhitespace;
    if AtEnd then Exit;

    Token := ReadToken;
    if Token = '' then Continue;

    if (LowerCase(Token) = 'end') then
      Exit
    else if (LowerCase(Token) = 'object') or (LowerCase(Token) = 'inherited') or
            (LowerCase(Token) = 'inline') then
      ParseObject(Sym)
    else
    begin
      { Property assignment - skip value }
      ReadUntilEOL;
      { Handle multi-line values }
      while not AtEnd do
      begin
        SkipWhitespace;
        if AtEnd then Exit;
        { Multi-line strings start with + or # on next line,
          collections start with <, items continue until > }
        if Peek in ['+', '#'] then
          ReadUntilEOL
        else if Peek = '<' then
        begin
          { Collection - skip until matching > }
          while not AtEnd do
          begin
            Token := ReadToken;
            if Token = '>' then Break;
            if (LowerCase(Token) = 'item') then
            begin
              { Skip item properties until 'end' }
              while not AtEnd do
              begin
                SkipWhitespace;
                Token := ReadToken;
                if LowerCase(Token) = 'end' then Break;
                ReadUntilEOL;
              end;
            end;
          end;
        end
        else if Peek = '(' then
        begin
          { Binary data - skip until ) }
          while (not AtEnd) and (Peek <> ')') do
            Advance;
          if not AtEnd then Advance;
        end
        else if Peek = '{' then
        begin
          // Hex data - skip until closing brace
          while (not AtEnd) and (Peek <> '}') do
            Advance;
          if not AtEnd then Advance;
        end
        else
          Break;
      end;
    end;
  end;
end;

function TFormParser.Parse(const Source, PackageName, RelativePath: string): TScipDocument;
var
  Token, Sym: string;
  Range: TScipRange;
begin
  FSource := Source;
  FPos := 1;
  FLine := 0;
  FCol := 0;
  FPackageName := PackageName;
  FRelativePath := RelativePath;
  SetLength(FOccurrences, 0);
  SetLength(FSymbols, 0);

  { DFM/LFM format starts with: object FormName: TFormClass }
  SkipWhitespace;
  Token := ReadToken;
  if (LowerCase(Token) = 'object') or (LowerCase(Token) = 'inherited') or
     (LowerCase(Token) = 'inline') then
  begin
    { Create a form-level symbol }
    Sym := MakeFormSymbol(PackageName, RelativePath);
    Range.StartLine := 0;
    Range.StartCol := 0;
    Range.EndLine := 0;
    Range.EndCol := Length(Token);
    AddOccurrence(Sym, ROLE_DEFINITION, Range);
    AddSymbol(Sym, RelativePath, KIND_MODULE, '');

    ParseObject(Sym);
  end;

  Result.RelativePath := RelativePath;
  Result.Language := 'pascal';
  Result.Occurrences := FOccurrences;
  Result.Symbols := FSymbols;
end;

function AnalyzeFormFile(const Source, PackageName, RelativePath: string): TScipDocument;
var
  Parser: TFormParser;
begin
  Parser := TFormParser.Create;
  try
    Result := Parser.Parse(Source, PackageName, RelativePath);
  finally
    Parser.Free;
  end;
end;

end.
