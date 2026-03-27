unit analyzer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, scip, symbols;

type
  TPascalAnalyzer = class
  private
    FSource: string;
    FLines: TStringList;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    FPackageName: string;
    FUnitName: string;
    FRelativePath: string;
    FOccurrences: array of TScipOccurrence;
    FSymbols: array of TScipSymbolInfo;
    FScopeStack: TStringList;

    { Lexer helpers }
    function Peek: Char;
    function PeekAhead(Offset: Integer): Char;
    function AtEnd: Boolean;
    procedure Advance;
    procedure SkipWhitespace;
    procedure SkipLineComment;
    procedure SkipBlockComment;
    procedure SkipOldStyleComment;
    procedure SkipWhitespaceAndComments;
    function ReadIdentifier: string;
    function ReadString: string;
    procedure SkipUntilSemicolon;
    procedure SkipBalancedParens;
    procedure SkipToKeyword(const Keywords: array of string);
    function CurrentWord: string;
    function MatchKeyword(const Kw: string): Boolean;
    function PeekKeyword: string;

    { Position tracking }
    function MakeRange(StartLine, StartCol, EndLine, EndCol: Integer): TScipRange;
    function CurrentRange(const Ident: string): TScipRange;

    { Symbol/occurrence helpers }
    procedure AddOccurrence(const Symbol: string; Roles: Integer; Range: TScipRange);
    procedure AddSymbol(const Symbol, DisplayName: string; Kind: Integer; Doc: string);
    function CurrentScope: string;
    procedure PushScope(const Symbol: string);
    procedure PopScope;

    { Parsers }
    procedure ParseUnit;
    procedure ParseProgram;
    procedure ParseLibrary;
    procedure ParseUsesClause;
    procedure ParseConstSection;
    procedure ParseVarSection;
    procedure ParseTypeSection;
    procedure ParseTypeDecl;
    procedure ParseClassType(const TypeName, TypeSymbol: string);
    procedure ParseRecordType(const TypeName, TypeSymbol: string);
    procedure ParseInterfaceType(const TypeName, TypeSymbol: string);
    procedure ParseEnumType(const TypeName, TypeSymbol: string);
    procedure ParseProcedureDecl(IsFunction: Boolean);
    procedure ParseMethodDecl(IsFunction: Boolean);
    procedure ParseParameters(const FuncSymbol: string; out Arity: Integer);
    procedure ParseBlock;
    procedure ParseImplementationSection;
    procedure ParseInterfaceSection;
    procedure ParseDeclarations;
  public
    constructor Create;
    destructor Destroy; override;
    function Analyze(const Source, PackageName, RelativePath: string): TScipDocument;
  end;

implementation

constructor TPascalAnalyzer.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FScopeStack := TStringList.Create;
end;

destructor TPascalAnalyzer.Destroy;
begin
  FScopeStack.Free;
  FLines.Free;
  inherited Destroy;
end;

{ Lexer helpers }

function TPascalAnalyzer.Peek: Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TPascalAnalyzer.PeekAhead(Offset: Integer): Char;
begin
  if (FPos + Offset) <= Length(FSource) then
    Result := FSource[FPos + Offset]
  else
    Result := #0;
end;

function TPascalAnalyzer.AtEnd: Boolean;
begin
  Result := FPos > Length(FSource);
end;

procedure TPascalAnalyzer.Advance;
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

procedure TPascalAnalyzer.SkipWhitespace;
begin
  while (not AtEnd) and (Peek in [' ', #9, #13, #10]) do
    Advance;
end;

procedure TPascalAnalyzer.SkipLineComment;
begin
  while (not AtEnd) and (Peek <> #10) do
    Advance;
end;

procedure TPascalAnalyzer.SkipBlockComment;
var
  Depth: Integer;
begin
  // Skip opening brace
  Advance;
  Depth := 1;
  while (not AtEnd) and (Depth > 0) do
  begin
    if Peek = '}' then
      Dec(Depth)
    else if Peek = '{' then
      Inc(Depth);
    Advance;
  end;
end;

procedure TPascalAnalyzer.SkipOldStyleComment;
begin
  { Skip opening (* }
  Advance;
  Advance;
  while not AtEnd do
  begin
    if (Peek = '*') and (PeekAhead(1) = ')') then
    begin
      Advance;
      Advance;
      Exit;
    end;
    Advance;
  end;
end;

procedure TPascalAnalyzer.SkipWhitespaceAndComments;
var
  Changed: Boolean;
begin
  repeat
    Changed := False;
    SkipWhitespace;
    if (not AtEnd) then
    begin
      if (Peek = '/') and (PeekAhead(1) = '/') then
      begin
        SkipLineComment;
        Changed := True;
      end
      else if Peek = '{' then
      begin
        SkipBlockComment;
        Changed := True;
      end
      else if (Peek = '(') and (PeekAhead(1) = '*') then
      begin
        SkipOldStyleComment;
        Changed := True;
      end;
    end;
  until not Changed;
end;

function TPascalAnalyzer.ReadIdentifier: string;
var
  Start: Integer;
begin
  Result := '';
  SkipWhitespaceAndComments;
  if AtEnd then Exit;
  if not (Peek in ['a'..'z', 'A'..'Z', '_']) then Exit;

  Start := FPos;
  while (not AtEnd) and (Peek in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    Advance;
  Result := Copy(FSource, Start, FPos - Start);
end;

function TPascalAnalyzer.ReadString: string;
begin
  Result := '';
  SkipWhitespaceAndComments;
  if AtEnd or (Peek <> '''') then Exit;
  Advance; { skip opening quote }
  while not AtEnd do
  begin
    if Peek = '''' then
    begin
      Advance;
      if (not AtEnd) and (Peek = '''') then
      begin
        Result := Result + '''';
        Advance;
      end
      else
        Exit;
    end
    else
    begin
      Result := Result + Peek;
      Advance;
    end;
  end;
end;

procedure TPascalAnalyzer.SkipUntilSemicolon;
var
  Depth: Integer;
begin
  Depth := 0;
  while not AtEnd do
  begin
    if Peek = '(' then
      Inc(Depth)
    else if Peek = ')' then
      Dec(Depth)
    else if (Peek = ';') and (Depth = 0) then
    begin
      Advance;
      Exit;
    end;
    Advance;
  end;
end;

procedure TPascalAnalyzer.SkipBalancedParens;
var
  Depth: Integer;
begin
  if Peek <> '(' then Exit;
  Depth := 0;
  while not AtEnd do
  begin
    if Peek = '(' then
      Inc(Depth)
    else if Peek = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Advance;
        Exit;
      end;
    end;
    Advance;
  end;
end;

procedure TPascalAnalyzer.SkipToKeyword(const Keywords: array of string);
var
  Word: string;
  I: Integer;
  SavePos, SaveLine, SaveCol: Integer;
begin
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    if AtEnd then Exit;

    if Peek in ['a'..'z', 'A'..'Z', '_'] then
    begin
      SavePos := FPos;
      SaveLine := FLine;
      SaveCol := FCol;
      Word := LowerCase(ReadIdentifier);
      for I := 0 to High(Keywords) do
      begin
        if Word = Keywords[I] then
        begin
          FPos := SavePos;
          FLine := SaveLine;
          FCol := SaveCol;
          Exit;
        end;
      end;
    end
    else
      Advance;
  end;
end;

function TPascalAnalyzer.CurrentWord: string;
var
  SavePos, SaveLine, SaveCol: Integer;
begin
  SavePos := FPos;
  SaveLine := FLine;
  SaveCol := FCol;
  Result := ReadIdentifier;
  FPos := SavePos;
  FLine := SaveLine;
  FCol := SaveCol;
end;

function TPascalAnalyzer.MatchKeyword(const Kw: string): Boolean;
var
  SavePos, SaveLine, SaveCol: Integer;
  Word: string;
begin
  SavePos := FPos;
  SaveLine := FLine;
  SaveCol := FCol;
  SkipWhitespaceAndComments;
  Word := ReadIdentifier;
  if LowerCase(Word) = LowerCase(Kw) then
    Result := True
  else
  begin
    FPos := SavePos;
    FLine := SaveLine;
    FCol := SaveCol;
    Result := False;
  end;
end;

function TPascalAnalyzer.PeekKeyword: string;
var
  SavePos, SaveLine, SaveCol: Integer;
begin
  SavePos := FPos;
  SaveLine := FLine;
  SaveCol := FCol;
  SkipWhitespaceAndComments;
  Result := LowerCase(ReadIdentifier);
  FPos := SavePos;
  FLine := SaveLine;
  FCol := SaveCol;
end;

{ Position tracking }

function TPascalAnalyzer.MakeRange(StartLine, StartCol, EndLine, EndCol: Integer): TScipRange;
begin
  Result.StartLine := StartLine;
  Result.StartCol := StartCol;
  Result.EndLine := EndLine;
  Result.EndCol := EndCol;
end;

function TPascalAnalyzer.CurrentRange(const Ident: string): TScipRange;
begin
  { FLine/FCol are 0-indexed after reading the identifier }
  Result.StartLine := FLine;
  Result.StartCol := FCol - Length(Ident);
  Result.EndLine := FLine;
  Result.EndCol := FCol;
  if Result.StartCol < 0 then Result.StartCol := 0;
end;

{ Symbol/occurrence helpers }

procedure TPascalAnalyzer.AddOccurrence(const Symbol: string; Roles: Integer; Range: TScipRange);
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

procedure TPascalAnalyzer.AddSymbol(const Symbol, DisplayName: string; Kind: Integer; Doc: string);
var
  Idx: Integer;
begin
  Idx := Length(FSymbols);
  SetLength(FSymbols, Idx + 1);
  FSymbols[Idx].Symbol := Symbol;
  FSymbols[Idx].DisplayName := DisplayName;
  FSymbols[Idx].Kind := Kind;
  FSymbols[Idx].EnclosingSymbol := CurrentScope;
  FSymbols[Idx].Documentation := nil;
  if Doc <> '' then
  begin
    FSymbols[Idx].Documentation := TStringList.Create;
    FSymbols[Idx].Documentation.Add(Doc);
  end;
end;

function TPascalAnalyzer.CurrentScope: string;
begin
  if FScopeStack.Count > 0 then
    Result := FScopeStack[FScopeStack.Count - 1]
  else
    Result := '';
end;

procedure TPascalAnalyzer.PushScope(const Symbol: string);
begin
  FScopeStack.Add(Symbol);
end;

procedure TPascalAnalyzer.PopScope;
begin
  if FScopeStack.Count > 0 then
    FScopeStack.Delete(FScopeStack.Count - 1);
end;

{ Parsers }

procedure TPascalAnalyzer.ParseUsesClause;
var
  UnitIdent: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  { 'uses' already consumed }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    IdentLine := FLine;
    IdentCol := FCol;
    UnitIdent := ReadIdentifier;
    if UnitIdent = '' then Break;

    { Handle dotted unit names like System.SysUtils }
    while (not AtEnd) and (Peek = '.') do
    begin
      Advance;
      UnitIdent := UnitIdent + '.' + ReadIdentifier;
    end;

    Sym := MakeModuleSymbol(FPackageName, UnitIdent);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := FLine;
    Range.EndCol := FCol;
    AddOccurrence(Sym, ROLE_IMPORT, Range);

    { Check for 'in' clause: uses MyUnit in 'myunit.pas' }
    SkipWhitespaceAndComments;
    if MatchKeyword('in') then
      ReadString;

    SkipWhitespaceAndComments;
    if AtEnd then Break;
    if Peek = ',' then
    begin
      Advance;
      Continue;
    end
    else if Peek = ';' then
    begin
      Advance;
      Break;
    end
    else
      Break;
  end;
end;

procedure TPascalAnalyzer.ParseConstSection;
var
  ConstName: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  { 'const' already consumed }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;

    { Check if next token is a keyword that ends const section }
    case PeekKeyword of
      'var', 'type', 'const', 'procedure', 'function', 'constructor',
      'destructor', 'begin', 'implementation', 'initialization',
      'finalization', 'end', 'class', 'public', 'private', 'protected',
      'published', 'property', 'resourcestring':
        Exit;
    end;

    IdentLine := FLine;
    IdentCol := FCol;
    ConstName := ReadIdentifier;
    if ConstName = '' then Exit;

    Sym := MakeConstantSymbol(FPackageName, FUnitName, ConstName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(ConstName);
    AddOccurrence(Sym, ROLE_DEFINITION, Range);
    AddSymbol(Sym, ConstName, KIND_CONSTANT, '');

    SkipUntilSemicolon;
  end;
end;

procedure TPascalAnalyzer.ParseVarSection;
var
  VarName: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
  Names: TStringList;
  I: Integer;
  Lines, Cols: array of Integer;
begin
  { 'var' already consumed }
  Names := TStringList.Create;
  try
    while not AtEnd do
    begin
      SkipWhitespaceAndComments;

      case PeekKeyword of
        'var', 'type', 'const', 'procedure', 'function', 'constructor',
        'destructor', 'begin', 'implementation', 'initialization',
        'finalization', 'end', 'class', 'public', 'private', 'protected',
        'published', 'property', 'resourcestring':
          Exit;
      end;

      Names.Clear;
      SetLength(Lines, 0);
      SetLength(Cols, 0);

      { Read comma-separated variable names }
      repeat
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        VarName := ReadIdentifier;
        if VarName = '' then Exit;

        Names.Add(VarName);
        SetLength(Lines, Length(Lines) + 1);
        Lines[High(Lines)] := IdentLine;
        SetLength(Cols, Length(Cols) + 1);
        Cols[High(Cols)] := IdentCol;

        SkipWhitespaceAndComments;
        if (not AtEnd) and (Peek = ',') then
          Advance
        else
          Break;
      until AtEnd;

      for I := 0 to Names.Count - 1 do
      begin
        Sym := MakeVariableSymbol(FPackageName, FUnitName, Names[I]);
        Range.StartLine := Lines[I];
        Range.StartCol := Cols[I];
        Range.EndLine := Lines[I];
        Range.EndCol := Cols[I] + Length(Names[I]);
        AddOccurrence(Sym, ROLE_DEFINITION, Range);
        AddSymbol(Sym, Names[I], KIND_VARIABLE, '');
      end;

      SkipUntilSemicolon;
    end;
  finally
    Names.Free;
  end;
end;

procedure TPascalAnalyzer.ParseEnumType(const TypeName, TypeSymbol: string);
var
  MemberName: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  { Opening '(' already consumed }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    if Peek = ')' then
    begin
      Advance;
      Exit;
    end;

    IdentLine := FLine;
    IdentCol := FCol;
    MemberName := ReadIdentifier;
    if MemberName = '' then Break;

    Sym := MakeEnumMemberSymbol(FPackageName, FUnitName, TypeName, MemberName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(MemberName);
    AddOccurrence(Sym, ROLE_DEFINITION, Range);
    AddSymbol(Sym, MemberName, KIND_ENUM_MEMBER, '');

    SkipWhitespaceAndComments;
    { May have = value assignment }
    if (not AtEnd) and (Peek = '=') then
    begin
      Advance;
      { Skip the value expression until , or ) }
      while (not AtEnd) and not (Peek in [',', ')']) do
        Advance;
    end;

    if (not AtEnd) and (Peek = ',') then
      Advance;
  end;
end;

procedure TPascalAnalyzer.ParseClassType(const TypeName, TypeSymbol: string);
var
  Kw, Ident: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  PushScope(TypeSymbol);
  try
    SkipWhitespaceAndComments;

    { Check for class heritage: class(TParent, IInterface) }
    if (not AtEnd) and (Peek = '(') then
      SkipBalancedParens;

    { Parse class body until 'end' }
    while not AtEnd do
    begin
      SkipWhitespaceAndComments;
      if AtEnd then Exit;

      Kw := PeekKeyword;

      if Kw = 'end' then
      begin
        ReadIdentifier; { consume 'end' }
        Exit;
      end
      else if (Kw = 'public') or (Kw = 'private') or (Kw = 'protected') or (Kw = 'published') or (Kw = 'strict') then
      begin
        ReadIdentifier; { consume visibility keyword }
        { 'strict' may be followed by 'private' or 'protected' }
        if Kw = 'strict' then
        begin
          SkipWhitespaceAndComments;
          Kw := PeekKeyword;
          if (Kw = 'private') or (Kw = 'protected') then
            ReadIdentifier;
        end;
      end
      else if (Kw = 'procedure') or (Kw = 'function') then
      begin
        ReadIdentifier; { consume 'procedure'/'function' }
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakeMethodSymbol(FPackageName, FUnitName, TypeName, Ident, 0);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_METHOD, '');
        end;
        SkipUntilSemicolon;
        { Skip method directives: virtual, abstract, override, etc. }
        while not AtEnd do
        begin
          Kw := PeekKeyword;
          if (Kw = 'virtual') or (Kw = 'abstract') or (Kw = 'override') or
             (Kw = 'reintroduce') or (Kw = 'overload') or (Kw = 'dynamic') or
             (Kw = 'cdecl') or (Kw = 'stdcall') or (Kw = 'inline') or
             (Kw = 'static') or (Kw = 'message') then
          begin
            ReadIdentifier;
            if Kw = 'message' then
            begin
              { message has an argument }
              SkipWhitespaceAndComments;
              if (not AtEnd) and (Peek in ['a'..'z','A'..'Z','_','0'..'9','''']) then
                SkipUntilSemicolon
              else
                SkipUntilSemicolon;
            end
            else
              SkipUntilSemicolon;
          end
          else
            Break;
        end;
      end
      else if (Kw = 'constructor') or (Kw = 'destructor') then
      begin
        ReadIdentifier; { consume keyword }
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakeMethodSymbol(FPackageName, FUnitName, TypeName, Ident, 0);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_METHOD, '');
        end;
        SkipUntilSemicolon;
        { Skip directives }
        while not AtEnd do
        begin
          Kw := PeekKeyword;
          if (Kw = 'virtual') or (Kw = 'abstract') or (Kw = 'override') or
             (Kw = 'reintroduce') or (Kw = 'overload') then
          begin
            ReadIdentifier;
            SkipUntilSemicolon;
          end
          else
            Break;
        end;
      end
      else if Kw = 'property' then
      begin
        ReadIdentifier; { consume 'property' }
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakePropertySymbol(FPackageName, FUnitName, TypeName, Ident);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_PROPERTY, '');
        end;
        SkipUntilSemicolon;
        { Skip property directives: default, stored, etc }
        while not AtEnd do
        begin
          Kw := PeekKeyword;
          if (Kw = 'default') or (Kw = 'stored') or (Kw = 'nodefault') then
          begin
            ReadIdentifier;
            SkipUntilSemicolon;
          end
          else
            Break;
        end;
      end
      else if Kw = 'class' then
      begin
        ReadIdentifier; { consume 'class' }
        { 'class procedure', 'class function', 'class var', 'class property' }
        { Let the loop handle the next keyword }
      end
      else
      begin
        { Field declaration: Name: Type; or Name, Name2: Type; }
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident = '' then
        begin
          Advance;
          Continue;
        end;

        Sym := MakeFieldSymbol(FPackageName, FUnitName, TypeName, Ident);
        Range.StartLine := IdentLine;
        Range.StartCol := IdentCol;
        Range.EndLine := IdentLine;
        Range.EndCol := IdentCol + Length(Ident);
        AddOccurrence(Sym, ROLE_DEFINITION, Range);
        AddSymbol(Sym, Ident, KIND_FIELD, '');

        { Handle comma-separated fields }
        SkipWhitespaceAndComments;
        while (not AtEnd) and (Peek = ',') do
        begin
          Advance;
          SkipWhitespaceAndComments;
          IdentLine := FLine;
          IdentCol := FCol;
          Ident := ReadIdentifier;
          if Ident = '' then Break;

          Sym := MakeFieldSymbol(FPackageName, FUnitName, TypeName, Ident);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_FIELD, '');
        end;

        SkipUntilSemicolon;
      end;
    end;
  finally
    PopScope;
  end;
end;

procedure TPascalAnalyzer.ParseRecordType(const TypeName, TypeSymbol: string);
var
  Kw, Ident: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  PushScope(TypeSymbol);
  try
    while not AtEnd do
    begin
      SkipWhitespaceAndComments;
      if AtEnd then Exit;

      Kw := PeekKeyword;

      if Kw = 'end' then
      begin
        ReadIdentifier;
        Exit;
      end
      else if Kw = 'case' then
      begin
        { Variant record - skip to field declarations }
        ReadIdentifier;
        SkipUntilSemicolon; { Skip case selector }
      end
      else if (Kw = 'procedure') or (Kw = 'function') then
      begin
        ReadIdentifier;
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakeMethodSymbol(FPackageName, FUnitName, TypeName, Ident, 0);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_METHOD, '');
        end;
        SkipUntilSemicolon;
      end
      else if (Kw = 'public') or (Kw = 'private') or (Kw = 'strict') then
      begin
        ReadIdentifier;
        if Kw = 'strict' then
        begin
          SkipWhitespaceAndComments;
          if PeekKeyword = 'private' then
            ReadIdentifier;
        end;
      end
      else if Kw = 'class' then
      begin
        ReadIdentifier;
      end
      else
      begin
        { Field }
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident = '' then
        begin
          { Could be a paren for variant record }
          if (not AtEnd) and (Peek in ['(', ')']) then
          begin
            if Peek = '(' then
              SkipBalancedParens
            else
              Advance;
            Continue;
          end;
          Advance;
          Continue;
        end;

        { Check if this is a number (variant record label) }
        if (Length(Ident) > 0) and (Ident[1] in ['0'..'9']) then
        begin
          SkipWhitespaceAndComments;
          if (not AtEnd) and (Peek = ':') then
          begin
            Advance;
            SkipWhitespaceAndComments;
            if (not AtEnd) and (Peek = '(') then
              SkipBalancedParens;
          end;
          Continue;
        end;

        Sym := MakeFieldSymbol(FPackageName, FUnitName, TypeName, Ident);
        Range.StartLine := IdentLine;
        Range.StartCol := IdentCol;
        Range.EndLine := IdentLine;
        Range.EndCol := IdentCol + Length(Ident);
        AddOccurrence(Sym, ROLE_DEFINITION, Range);
        AddSymbol(Sym, Ident, KIND_FIELD, '');

        { Handle comma-separated fields }
        SkipWhitespaceAndComments;
        while (not AtEnd) and (Peek = ',') do
        begin
          Advance;
          SkipWhitespaceAndComments;
          IdentLine := FLine;
          IdentCol := FCol;
          Ident := ReadIdentifier;
          if Ident = '' then Break;
          Sym := MakeFieldSymbol(FPackageName, FUnitName, TypeName, Ident);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_FIELD, '');
        end;

        SkipUntilSemicolon;
      end;
    end;
  finally
    PopScope;
  end;
end;

procedure TPascalAnalyzer.ParseInterfaceType(const TypeName, TypeSymbol: string);
var
  Kw, Ident: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  PushScope(TypeSymbol);
  try
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = '(') then
      SkipBalancedParens;

    { Check for GUID }
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = '[') then
    begin
      while (not AtEnd) and (Peek <> ']') do
        Advance;
      if not AtEnd then Advance;
    end;

    while not AtEnd do
    begin
      SkipWhitespaceAndComments;
      Kw := PeekKeyword;

      if Kw = 'end' then
      begin
        ReadIdentifier;
        Exit;
      end
      else if (Kw = 'procedure') or (Kw = 'function') then
      begin
        ReadIdentifier;
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakeMethodSymbol(FPackageName, FUnitName, TypeName, Ident, 0);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_METHOD, '');
        end;
        SkipUntilSemicolon;
      end
      else if Kw = 'property' then
      begin
        ReadIdentifier;
        SkipWhitespaceAndComments;
        IdentLine := FLine;
        IdentCol := FCol;
        Ident := ReadIdentifier;
        if Ident <> '' then
        begin
          Sym := MakePropertySymbol(FPackageName, FUnitName, TypeName, Ident);
          Range.StartLine := IdentLine;
          Range.StartCol := IdentCol;
          Range.EndLine := IdentLine;
          Range.EndCol := IdentCol + Length(Ident);
          AddOccurrence(Sym, ROLE_DEFINITION, Range);
          AddSymbol(Sym, Ident, KIND_PROPERTY, '');
        end;
        SkipUntilSemicolon;
      end
      else
      begin
        Advance;
      end;
    end;
  finally
    PopScope;
  end;
end;

procedure TPascalAnalyzer.ParseTypeDecl;
var
  TypeName, Kw: string;
  IdentLine, IdentCol: Integer;
  TypeSym: string;
  Range: TScipRange;
  Kind: Integer;
begin
  SkipWhitespaceAndComments;
  IdentLine := FLine;
  IdentCol := FCol;
  TypeName := ReadIdentifier;
  if TypeName = '' then Exit;

  SkipWhitespaceAndComments;
  { Skip generic params: TypeName<T> }
  if (not AtEnd) and (Peek = '<') then
  begin
    while (not AtEnd) and (Peek <> '>') do
      Advance;
    if not AtEnd then Advance;
    SkipWhitespaceAndComments;
  end;

  if AtEnd or (Peek <> '=') then
  begin
    SkipUntilSemicolon;
    Exit;
  end;
  Advance; { consume '=' }
  SkipWhitespaceAndComments;

  Kw := PeekKeyword;

  if Kw = 'class' then
  begin
    ReadIdentifier;
    SkipWhitespaceAndComments;

    { Forward declaration: TFoo = class; }
    if (not AtEnd) and (Peek = ';') then
    begin
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_CLASS, '');
      Advance;
      Exit;
    end;

    { Check for 'class of' (metaclass) }
    if PeekKeyword = 'of' then
    begin
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_TYPE, '');
      SkipUntilSemicolon;
      Exit;
    end;

    TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(TypeName);
    AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
    AddSymbol(TypeSym, TypeName, KIND_CLASS, '');
    ParseClassType(TypeName, TypeSym);
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = ';') then Advance;
  end
  else if Kw = 'record' then
  begin
    ReadIdentifier;
    TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(TypeName);
    AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
    AddSymbol(TypeSym, TypeName, KIND_CLASS, '');
    ParseRecordType(TypeName, TypeSym);
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = ';') then Advance;
  end
  else if Kw = 'interface' then
  begin
    ReadIdentifier;
    SkipWhitespaceAndComments;

    { Forward declaration }
    if (not AtEnd) and (Peek = ';') then
    begin
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_INTERFACE, '');
      Advance;
      Exit;
    end;

    TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(TypeName);
    AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
    AddSymbol(TypeSym, TypeName, KIND_INTERFACE, '');
    ParseInterfaceType(TypeName, TypeSym);
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = ';') then Advance;
  end
  else if Kw = 'dispinterface' then
  begin
    ReadIdentifier;
    TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(TypeName);
    AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
    AddSymbol(TypeSym, TypeName, KIND_INTERFACE, '');
    ParseInterfaceType(TypeName, TypeSym);
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = ';') then Advance;
  end
  else if Kw = 'object' then
  begin
    ReadIdentifier;
    TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
    Range.StartLine := IdentLine;
    Range.StartCol := IdentCol;
    Range.EndLine := IdentLine;
    Range.EndCol := IdentCol + Length(TypeName);
    AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
    AddSymbol(TypeSym, TypeName, KIND_CLASS, '');
    ParseClassType(TypeName, TypeSym);
    SkipWhitespaceAndComments;
    if (not AtEnd) and (Peek = ';') then Advance;
  end
  else if Kw = 'packed' then
  begin
    ReadIdentifier;
    Kw := PeekKeyword;
    if Kw = 'record' then
    begin
      ReadIdentifier;
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_CLASS, '');
      ParseRecordType(TypeName, TypeSym);
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
    end
    else
    begin
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_TYPE, '');
      SkipUntilSemicolon;
    end;
  end
  else
  begin
    { Check for enum: TMyEnum = (val1, val2, ...) }
    if (not AtEnd) and (Peek = '(') then
    begin
      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, KIND_ENUM, '');
      Advance; { consume '(' }
      ParseEnumType(TypeName, TypeSym);
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
    end
    else
    begin
      { Simple type alias, subrange, set, pointer, etc. }
      if Kw = 'set' then
        Kind := KIND_TYPE
      else if Kw = 'array' then
        Kind := KIND_TYPE
      else
        Kind := KIND_TYPE;

      TypeSym := MakeTypeSymbol(FPackageName, FUnitName, TypeName);
      Range.StartLine := IdentLine;
      Range.StartCol := IdentCol;
      Range.EndLine := IdentLine;
      Range.EndCol := IdentCol + Length(TypeName);
      AddOccurrence(TypeSym, ROLE_DEFINITION, Range);
      AddSymbol(TypeSym, TypeName, Kind, '');
      SkipUntilSemicolon;
    end;
  end;
end;

procedure TPascalAnalyzer.ParseTypeSection;
begin
  { 'type' already consumed }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;

    case PeekKeyword of
      'var', 'const', 'type', 'procedure', 'function', 'constructor',
      'destructor', 'begin', 'implementation', 'initialization',
      'finalization', 'end', 'resourcestring':
        Exit;
      '':
        Exit;
    end;

    ParseTypeDecl;
  end;
end;

procedure TPascalAnalyzer.ParseParameters(const FuncSymbol: string; out Arity: Integer);
var
  ParamName: string;
begin
  Arity := 0;
  SkipWhitespaceAndComments;
  if AtEnd or (Peek <> '(') then Exit;

  Advance; { consume '(' }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    if Peek = ')' then
    begin
      Advance;
      Exit;
    end;

    { Skip 'var', 'const', 'out', 'constref' modifiers }
    case PeekKeyword of
      'var', 'const', 'out', 'constref':
        ReadIdentifier;
    end;

    { Read parameter names (comma separated before colon) }
    repeat
      SkipWhitespaceAndComments;
      ParamName := ReadIdentifier;
      if ParamName <> '' then
        Inc(Arity);
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ',') then
        Advance
      else
        Break;
    until AtEnd;

    { Skip : Type and optional default }
    if (not AtEnd) and (Peek = ':') then
    begin
      Advance;
      { Skip type - could be complex (array of, function type, etc) }
      while (not AtEnd) and not (Peek in [';', ')']) do
      begin
        if Peek = '(' then
          SkipBalancedParens
        else
          Advance;
      end;
    end;

    if (not AtEnd) and (Peek = ';') then
      Advance;
  end;
end;

procedure TPascalAnalyzer.ParseProcedureDecl(IsFunction: Boolean);
var
  Name: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
  Arity: Integer;
  Kw: string;
  BeginDepth: Integer;
begin
  { 'procedure'/'function' already consumed }
  SkipWhitespaceAndComments;
  IdentLine := FLine;
  IdentCol := FCol;
  Name := ReadIdentifier;
  if Name = '' then
  begin
    SkipUntilSemicolon;
    Exit;
  end;

  { Check if this is a method implementation: TFoo.DoSomething }
  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = '.') then
  begin
    { This is a qualified method implementation }
    ParseMethodDecl(IsFunction);
    Exit;
  end;

  ParseParameters('', Arity);

  { Function return type }
  SkipWhitespaceAndComments;
  if IsFunction and (not AtEnd) and (Peek = ':') then
  begin
    Advance;
    while (not AtEnd) and (Peek <> ';') do
      Advance;
  end;

  Sym := MakeFunctionSymbol(FPackageName, FUnitName, Name, Arity);
  Range.StartLine := IdentLine;
  Range.StartCol := IdentCol;
  Range.EndLine := IdentLine;
  Range.EndCol := IdentCol + Length(Name);
  AddOccurrence(Sym, ROLE_DEFINITION, Range);
  AddSymbol(Sym, Name, KIND_FUNCTION, '');

  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = ';') then Advance;

  { Check for directives and forward }
  while not AtEnd do
  begin
    Kw := PeekKeyword;
    if (Kw = 'forward') or (Kw = 'external') then
    begin
      ReadIdentifier;
      SkipUntilSemicolon;
      Exit;
    end
    else if (Kw = 'cdecl') or (Kw = 'stdcall') or (Kw = 'pascal') or
            (Kw = 'register') or (Kw = 'safecall') or (Kw = 'inline') or
            (Kw = 'overload') or (Kw = 'export') or (Kw = 'assembler') or
            (Kw = 'nostackframe') or (Kw = 'interrupt') then
    begin
      ReadIdentifier;
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
    end
    else
      Break;
  end;

  { Parse local declarations and body }
  PushScope(Sym);
  try
    while not AtEnd do
    begin
      Kw := PeekKeyword;
      if Kw = 'var' then
      begin
        ReadIdentifier;
        ParseVarSection;
      end
      else if Kw = 'const' then
      begin
        ReadIdentifier;
        ParseConstSection;
      end
      else if Kw = 'type' then
      begin
        ReadIdentifier;
        ParseTypeSection;
      end
      else if (Kw = 'procedure') or (Kw = 'function') then
      begin
        ReadIdentifier;
        ParseProcedureDecl(Kw = 'function');
      end
      else if Kw = 'begin' then
      begin
        ReadIdentifier;
        { Skip begin..end block }
        BeginDepth := 1;
        while (not AtEnd) and (BeginDepth > 0) do
        begin
          Kw := PeekKeyword;
          if (Kw = 'begin') or (Kw = 'case') or (Kw = 'try') then
          begin
            ReadIdentifier;
            Inc(BeginDepth);
          end
          else if Kw = 'end' then
          begin
            ReadIdentifier;
            Dec(BeginDepth);
          end
          else if Kw <> '' then
            ReadIdentifier
          else
            Advance;
        end;
        SkipWhitespaceAndComments;
        if (not AtEnd) and (Peek = ';') then Advance;
        Exit;
      end
      else if Kw = 'asm' then
      begin
        ReadIdentifier;
        while not AtEnd do
        begin
          if PeekKeyword = 'end' then
          begin
            ReadIdentifier;
            Break;
          end;
          Advance;
        end;
        SkipWhitespaceAndComments;
        if (not AtEnd) and (Peek = ';') then Advance;
        Exit;
      end
      else
        Break;
    end;
  finally
    PopScope;
  end;
end;

procedure TPascalAnalyzer.ParseMethodDecl(IsFunction: Boolean);
var
  Kw: string;
  Arity: Integer;
  BeginDepth: Integer;
begin
  // Method implementations reference declarations already indexed in class/record.
  // The caller detected '.' as next char after the type name.
  Advance; // consume '.'
  ReadIdentifier; // consume method name

  ParseParameters('', Arity);

  { Function return type }
  SkipWhitespaceAndComments;
  if IsFunction and (not AtEnd) and (Peek = ':') then
  begin
    Advance;
    while (not AtEnd) and (Peek <> ';') do
      Advance;
  end;

  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = ';') then Advance;

  { Skip directives }
  while not AtEnd do
  begin
    Kw := PeekKeyword;
    if (Kw = 'cdecl') or (Kw = 'stdcall') or (Kw = 'pascal') or
       (Kw = 'register') or (Kw = 'safecall') or (Kw = 'inline') or
       (Kw = 'overload') or (Kw = 'assembler') then
    begin
      ReadIdentifier;
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
    end
    else
      Break;
  end;

  { Parse body }
  while not AtEnd do
  begin
    Kw := PeekKeyword;
    if Kw = 'var' then
    begin
      ReadIdentifier;
      ParseVarSection;
    end
    else if Kw = 'const' then
    begin
      ReadIdentifier;
      ParseConstSection;
    end
    else if Kw = 'type' then
    begin
      ReadIdentifier;
      ParseTypeSection;
    end
    else if (Kw = 'procedure') or (Kw = 'function') then
    begin
      ReadIdentifier;
      ParseProcedureDecl(Kw = 'function');
    end
    else if Kw = 'begin' then
    begin
      ReadIdentifier;
      BeginDepth := 1;
      while (not AtEnd) and (BeginDepth > 0) do
      begin
        Kw := PeekKeyword;
        if (Kw = 'begin') or (Kw = 'case') or (Kw = 'try') then
        begin
          ReadIdentifier;
          Inc(BeginDepth);
        end
        else if Kw = 'end' then
        begin
          ReadIdentifier;
          Dec(BeginDepth);
        end
        else if Kw <> '' then
          ReadIdentifier
        else
          Advance;
      end;
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
      Exit;
    end
    else if Kw = 'asm' then
    begin
      ReadIdentifier;
      while not AtEnd do
      begin
        if PeekKeyword = 'end' then
        begin
          ReadIdentifier;
          Break;
        end;
        Advance;
      end;
      SkipWhitespaceAndComments;
      if (not AtEnd) and (Peek = ';') then Advance;
      Exit;
    end
    else
      Break;
  end;
end;

procedure TPascalAnalyzer.ParseBlock;
var
  Kw: string;
  BeginDepth: Integer;
begin
  if not MatchKeyword('begin') then Exit;

  BeginDepth := 1;
  while (not AtEnd) and (BeginDepth > 0) do
  begin
    Kw := PeekKeyword;
    if (Kw = 'begin') or (Kw = 'case') or (Kw = 'try') then
    begin
      ReadIdentifier;
      Inc(BeginDepth);
    end
    else if Kw = 'end' then
    begin
      ReadIdentifier;
      Dec(BeginDepth);
    end
    else if Kw <> '' then
      ReadIdentifier
    else
      Advance;
  end;
end;

procedure TPascalAnalyzer.ParseDeclarations;
var
  Kw: string;
begin
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    if AtEnd then Exit;

    Kw := PeekKeyword;

    if Kw = 'uses' then
    begin
      ReadIdentifier;
      ParseUsesClause;
    end
    else if Kw = 'type' then
    begin
      ReadIdentifier;
      ParseTypeSection;
    end
    else if Kw = 'const' then
    begin
      ReadIdentifier;
      ParseConstSection;
    end
    else if Kw = 'resourcestring' then
    begin
      ReadIdentifier;
      ParseConstSection; { resource strings are like constants }
    end
    else if Kw = 'var' then
    begin
      ReadIdentifier;
      ParseVarSection;
    end
    else if Kw = 'threadvar' then
    begin
      ReadIdentifier;
      ParseVarSection;
    end
    else if (Kw = 'procedure') or (Kw = 'function') then
    begin
      ReadIdentifier;
      ParseProcedureDecl(Kw = 'function');
    end
    else if (Kw = 'constructor') or (Kw = 'destructor') then
    begin
      ReadIdentifier;
      ParseProcedureDecl(False);
    end
    else
      Exit;
  end;
end;

procedure TPascalAnalyzer.ParseInterfaceSection;
begin
  { 'interface' already consumed }
  ParseDeclarations;
end;

procedure TPascalAnalyzer.ParseImplementationSection;
begin
  { 'implementation' already consumed }
  ParseDeclarations;
end;

procedure TPascalAnalyzer.ParseUnit;
var
  UnitIdent: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
  Kw: string;
begin
  { 'unit' already consumed }
  SkipWhitespaceAndComments;
  IdentLine := FLine;
  IdentCol := FCol;
  UnitIdent := ReadIdentifier;

  { Handle dotted unit names }
  while (not AtEnd) and (Peek = '.') do
  begin
    Advance;
    UnitIdent := UnitIdent + '.' + ReadIdentifier;
  end;

  FUnitName := UnitIdent;

  Sym := MakeModuleSymbol(FPackageName, FUnitName);
  Range.StartLine := IdentLine;
  Range.StartCol := IdentCol;
  Range.EndLine := FLine;
  Range.EndCol := FCol;
  AddOccurrence(Sym, ROLE_DEFINITION, Range);
  AddSymbol(Sym, FUnitName, KIND_MODULE, '');

  PushScope(Sym);

  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = ';') then Advance;

  { Parse until end of file }
  while not AtEnd do
  begin
    SkipWhitespaceAndComments;
    Kw := PeekKeyword;

    if Kw = 'interface' then
    begin
      ReadIdentifier;
      ParseInterfaceSection;
    end
    else if Kw = 'implementation' then
    begin
      ReadIdentifier;
      ParseImplementationSection;
    end
    else if Kw = 'initialization' then
    begin
      ReadIdentifier;
      { Skip initialization block }
      SkipToKeyword(['finalization', 'end']);
    end
    else if Kw = 'finalization' then
    begin
      ReadIdentifier;
      SkipToKeyword(['end']);
    end
    else if Kw = 'end' then
    begin
      ReadIdentifier;
      Break;
    end
    else if Kw = 'begin' then
    begin
      ParseBlock;
      Break;
    end
    else if Kw <> '' then
      ReadIdentifier
    else
      Advance;
  end;

  PopScope;
end;

procedure TPascalAnalyzer.ParseProgram;
var
  ProgName: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  { 'program' already consumed }
  SkipWhitespaceAndComments;
  IdentLine := FLine;
  IdentCol := FCol;
  ProgName := ReadIdentifier;
  FUnitName := ProgName;

  Sym := MakeModuleSymbol(FPackageName, FUnitName);
  Range.StartLine := IdentLine;
  Range.StartCol := IdentCol;
  Range.EndLine := IdentLine;
  Range.EndCol := IdentCol + Length(ProgName);
  AddOccurrence(Sym, ROLE_DEFINITION, Range);
  AddSymbol(Sym, FUnitName, KIND_MODULE, '');

  PushScope(Sym);

  { Skip optional program parameters: program Foo(Input, Output); }
  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = '(') then
    SkipBalancedParens;
  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = ';') then Advance;

  ParseDeclarations;

  { Parse main block }
  if PeekKeyword = 'begin' then
    ParseBlock;

  PopScope;
end;

procedure TPascalAnalyzer.ParseLibrary;
var
  LibName: string;
  IdentLine, IdentCol: Integer;
  Sym: string;
  Range: TScipRange;
begin
  { 'library' already consumed }
  SkipWhitespaceAndComments;
  IdentLine := FLine;
  IdentCol := FCol;
  LibName := ReadIdentifier;
  FUnitName := LibName;

  Sym := MakeModuleSymbol(FPackageName, FUnitName);
  Range.StartLine := IdentLine;
  Range.StartCol := IdentCol;
  Range.EndLine := IdentLine;
  Range.EndCol := IdentCol + Length(LibName);
  AddOccurrence(Sym, ROLE_DEFINITION, Range);
  AddSymbol(Sym, FUnitName, KIND_MODULE, '');

  PushScope(Sym);

  SkipWhitespaceAndComments;
  if (not AtEnd) and (Peek = ';') then Advance;

  ParseDeclarations;

  if PeekKeyword = 'begin' then
    ParseBlock;

  PopScope;
end;

function TPascalAnalyzer.Analyze(const Source, PackageName, RelativePath: string): TScipDocument;
var
  Kw: string;
begin
  FSource := Source;
  FPos := 1;
  FLine := 0;
  FCol := 0;
  FPackageName := PackageName;
  FRelativePath := RelativePath;
  FUnitName := ChangeFileExt(ExtractFileName(RelativePath), '');
  SetLength(FOccurrences, 0);
  SetLength(FSymbols, 0);
  FScopeStack.Clear;

  FLines.Text := Source;

  SkipWhitespaceAndComments;
  Kw := PeekKeyword;

  if Kw = 'unit' then
  begin
    ReadIdentifier;
    ParseUnit;
  end
  else if Kw = 'program' then
  begin
    ReadIdentifier;
    ParseProgram;
  end
  else if Kw = 'library' then
  begin
    ReadIdentifier;
    ParseLibrary;
  end
  else
  begin
    { Include file or file without header - parse as declarations }
    ParseDeclarations;
    if PeekKeyword = 'begin' then
      ParseBlock;
  end;

  Result.RelativePath := RelativePath;
  Result.Language := 'pascal';
  Result.Occurrences := FOccurrences;
  Result.Symbols := FSymbols;
end;

end.
