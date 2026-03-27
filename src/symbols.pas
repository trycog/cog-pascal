unit symbols;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  SCIP_SCHEME  = 'scip-pascal';
  SCIP_MANAGER = '.';
  SCIP_VERSION = 'unversioned';

function MakeModuleSymbol(const PackageName, UnitName: string): string;
function MakeTypeSymbol(const PackageName, UnitName, TypeName: string): string;
function MakeFunctionSymbol(const PackageName, UnitName, FuncName: string; Arity: Integer): string;
function MakeMethodSymbol(const PackageName, UnitName, TypeName, MethodName: string; Arity: Integer): string;
function MakeFieldSymbol(const PackageName, UnitName, TypeName, FieldName: string): string;
function MakeVariableSymbol(const PackageName, UnitName, VarName: string): string;
function MakeConstantSymbol(const PackageName, UnitName, ConstName: string): string;
function MakePropertySymbol(const PackageName, UnitName, TypeName, PropName: string): string;
function MakeEnumMemberSymbol(const PackageName, UnitName, EnumName, MemberName: string): string;
function MakeParameterSymbol(const PackageName, UnitName, FuncName: string; Arity: Integer; const ParamName: string): string;
function MakeFormSymbol(const PackageName, FormPath: string): string;
function MakeFormComponentSymbol(const PackageName, FormPath, ComponentName, ComponentClass: string): string;

implementation

function EscapeIdentifier(const Name: string): string;
var
  I: Integer;
  NeedEscape: Boolean;
begin
  NeedEscape := False;
  for I := 1 to Length(Name) do
  begin
    if not (Name[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '+', '-', '$']) then
    begin
      NeedEscape := True;
      Break;
    end;
  end;

  if not NeedEscape then
  begin
    Result := Name;
    Exit;
  end;

  Result := '`';
  for I := 1 to Length(Name) do
  begin
    if Name[I] = '`' then
      Result := Result + '``'
    else
      Result := Result + Name[I];
  end;
  Result := Result + '`';
end;

function BuildSymbol(const PackageName: string; const Descriptors: string): string;
begin
  Result := SCIP_SCHEME + ' ' + SCIP_MANAGER + ' ' +
            EscapeIdentifier(PackageName) + ' ' +
            SCIP_VERSION + ' ' + Descriptors;
end;

function MakeModuleSymbol(const PackageName, UnitName: string): string;
begin
  Result := BuildSymbol(PackageName, EscapeIdentifier(UnitName) + '#');
end;

function MakeTypeSymbol(const PackageName, UnitName, TypeName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(TypeName) + '#');
end;

function MakeFunctionSymbol(const PackageName, UnitName, FuncName: string; Arity: Integer): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(FuncName) + '(' + IntToStr(Arity) + ').');
end;

function MakeMethodSymbol(const PackageName, UnitName, TypeName, MethodName: string; Arity: Integer): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(TypeName) + '#' +
    EscapeIdentifier(MethodName) + '(' + IntToStr(Arity) + ').');
end;

function MakeFieldSymbol(const PackageName, UnitName, TypeName, FieldName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(TypeName) + '#' +
    EscapeIdentifier(FieldName) + '.');
end;

function MakeVariableSymbol(const PackageName, UnitName, VarName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(VarName) + '.');
end;

function MakeConstantSymbol(const PackageName, UnitName, ConstName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(ConstName) + '.');
end;

function MakePropertySymbol(const PackageName, UnitName, TypeName, PropName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(TypeName) + '#' +
    EscapeIdentifier(PropName) + '.');
end;

function MakeEnumMemberSymbol(const PackageName, UnitName, EnumName, MemberName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(EnumName) + '#' +
    EscapeIdentifier(MemberName) + '.');
end;

function MakeParameterSymbol(const PackageName, UnitName, FuncName: string; Arity: Integer; const ParamName: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(UnitName) + '#' + EscapeIdentifier(FuncName) + '(' + IntToStr(Arity) + ').' +
    EscapeIdentifier(ParamName) + '.');
end;

function MakeFormSymbol(const PackageName, FormPath: string): string;
begin
  Result := BuildSymbol(PackageName, EscapeIdentifier(FormPath) + '#');
end;

function MakeFormComponentSymbol(const PackageName, FormPath, ComponentName, ComponentClass: string): string;
begin
  Result := BuildSymbol(PackageName,
    EscapeIdentifier(FormPath) + '#' + EscapeIdentifier(ComponentName) + '.');
end;

end.
