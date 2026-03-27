unit scip;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { Protobuf wire types }
  WIRE_VARINT    = 0;
  WIRE_DELIMITED = 2;

  { SCIP Symbol Roles (bitfield) }
  ROLE_DEFINITION  = $1;
  ROLE_IMPORT      = $2;
  ROLE_WRITE       = $4;
  ROLE_READ        = $8;

  { SCIP Symbol Kinds }
  KIND_UNKNOWN       = 0;
  KIND_CLASS         = 7;
  KIND_CONSTANT      = 8;
  KIND_ENUM          = 13;
  KIND_ENUM_MEMBER   = 14;
  KIND_FIELD         = 15;
  KIND_FUNCTION      = 17;
  KIND_INTERFACE     = 21;
  KIND_METHOD        = 27;
  KIND_MODULE        = 29;
  KIND_NAMESPACE     = 30;
  KIND_PARAMETER     = 37;
  KIND_PROPERTY      = 39;
  KIND_TYPE          = 54;
  KIND_VARIABLE      = 59;

  { SCIP protobuf field numbers }

  { Index fields }
  FIELD_INDEX_METADATA         = 1;
  FIELD_INDEX_DOCUMENTS        = 2;
  FIELD_INDEX_EXTERNAL_SYMBOLS = 3;

  { Metadata fields }
  FIELD_META_VERSION           = 1;
  FIELD_META_TOOL_INFO         = 2;
  FIELD_META_PROJECT_ROOT      = 3;
  FIELD_META_TEXT_ENCODING     = 4;

  { ToolInfo fields }
  FIELD_TOOL_NAME              = 1;
  FIELD_TOOL_VERSION           = 2;
  FIELD_TOOL_ARGUMENTS         = 3;

  { Document fields }
  FIELD_DOC_RELATIVE_PATH      = 1;
  FIELD_DOC_OCCURRENCES        = 2;
  FIELD_DOC_SYMBOLS            = 3;
  FIELD_DOC_LANGUAGE           = 4;

  { Occurrence fields }
  FIELD_OCC_RANGE              = 1;
  FIELD_OCC_SYMBOL             = 2;
  FIELD_OCC_SYMBOL_ROLES       = 3;
  FIELD_OCC_ENCLOSING_RANGE    = 7;

  { SymbolInformation fields }
  FIELD_SYM_SYMBOL             = 1;
  FIELD_SYM_DOCUMENTATION      = 3;
  FIELD_SYM_RELATIONSHIPS      = 4;
  FIELD_SYM_KIND               = 5;
  FIELD_SYM_DISPLAY_NAME       = 6;
  FIELD_SYM_ENCLOSING_SYMBOL   = 8;

  { Relationship fields }
  FIELD_REL_SYMBOL             = 1;
  FIELD_REL_IS_REFERENCE       = 2;
  FIELD_REL_IS_IMPLEMENTATION  = 3;
  FIELD_REL_IS_TYPE_DEFINITION = 4;
  FIELD_REL_IS_DEFINITION      = 5;

type
  TScipRange = record
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
  end;

  TScipRelationship = record
    Symbol: string;
    IsReference: Boolean;
    IsImplementation: Boolean;
    IsTypeDefinition: Boolean;
    IsDefinition: Boolean;
  end;

  TScipOccurrence = record
    Range: TScipRange;
    Symbol: string;
    SymbolRoles: Integer;
    EnclosingRange: TScipRange;
    HasEnclosingRange: Boolean;
  end;

  TScipSymbolInfo = record
    Symbol: string;
    Documentation: TStringList;
    Relationships: array of TScipRelationship;
    Kind: Integer;
    DisplayName: string;
    EnclosingSymbol: string;
  end;

  TScipDocument = record
    RelativePath: string;
    Language: string;
    Occurrences: array of TScipOccurrence;
    Symbols: array of TScipSymbolInfo;
  end;

  TScipToolInfo = record
    Name: string;
    Version: string;
    Arguments: TStringList;
  end;

  TScipMetadata = record
    Version: Integer;
    ToolInfo: TScipToolInfo;
    ProjectRoot: string;
    TextDocumentEncoding: Integer;
  end;

  TScipIndex = record
    Metadata: TScipMetadata;
    Documents: array of TScipDocument;
  end;

  { Protobuf encoder }
  TProtobufEncoder = class
  private
    FStream: TMemoryStream;
    procedure WriteVarint(Value: QWord);
    procedure WriteTag(FieldNumber: Integer; WireType: Integer);
    procedure WriteStringField(FieldNumber: Integer; const Value: string);
    procedure WriteInt32Field(FieldNumber: Integer; Value: Integer);
    procedure WriteBoolField(FieldNumber: Integer; Value: Boolean);
    procedure WriteMessageField(FieldNumber: Integer; SubEncoder: TProtobufEncoder);
    procedure WritePackedInt32Field(FieldNumber: Integer; const Values: array of Integer);
    procedure WriteRepeatedMessageField(FieldNumber: Integer; const Encoders: array of TProtobufEncoder);
    procedure WriteRepeatedStringField(FieldNumber: Integer; Strings: TStringList);
  public
    constructor Create;
    destructor Destroy; override;
    function GetBytes: TBytes;
    function Size: Int64;

    procedure EncodeToolInfo(const Info: TScipToolInfo);
    procedure EncodeMetadata(const Meta: TScipMetadata);
    procedure EncodeRelationship(const Rel: TScipRelationship);
    procedure EncodeOccurrence(const Occ: TScipOccurrence);
    procedure EncodeSymbolInfo(const Sym: TScipSymbolInfo);
    procedure EncodeDocument(const Doc: TScipDocument);
    procedure EncodeIndex(const Idx: TScipIndex);
  end;

procedure WriteScipIndex(const Idx: TScipIndex; const OutputPath: string);

implementation

{ TProtobufEncoder }

constructor TProtobufEncoder.Create;
begin
  inherited Create;
  FStream := TMemoryStream.Create;
end;

destructor TProtobufEncoder.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

function TProtobufEncoder.GetBytes: TBytes;
begin
  Result := nil;
  SetLength(Result, FStream.Size);
  if FStream.Size > 0 then
  begin
    FStream.Position := 0;
    FStream.ReadBuffer(Result[0], FStream.Size);
  end;
end;

function TProtobufEncoder.Size: Int64;
begin
  Result := FStream.Size;
end;

procedure TProtobufEncoder.WriteVarint(Value: QWord);
var
  B: Byte;
begin
  while Value > $7F do
  begin
    B := Byte(Value and $7F) or $80;
    FStream.WriteBuffer(B, 1);
    Value := Value shr 7;
  end;
  B := Byte(Value);
  FStream.WriteBuffer(B, 1);
end;

procedure TProtobufEncoder.WriteTag(FieldNumber: Integer; WireType: Integer);
begin
  WriteVarint(QWord((FieldNumber shl 3) or WireType));
end;

procedure TProtobufEncoder.WriteStringField(FieldNumber: Integer; const Value: string);
var
  Len: Integer;
begin
  if Value = '' then Exit;
  WriteTag(FieldNumber, WIRE_DELIMITED);
  Len := Length(Value);
  WriteVarint(QWord(Len));
  FStream.WriteBuffer(Value[1], Len);
end;

procedure TProtobufEncoder.WriteInt32Field(FieldNumber: Integer; Value: Integer);
begin
  if Value = 0 then Exit;
  WriteTag(FieldNumber, WIRE_VARINT);
  if Value < 0 then
    WriteVarint(QWord(Int64(Value) and $FFFFFFFFFFFFFFFF))
  else
    WriteVarint(QWord(Value));
end;

procedure TProtobufEncoder.WriteBoolField(FieldNumber: Integer; Value: Boolean);
begin
  if not Value then Exit;
  WriteTag(FieldNumber, WIRE_VARINT);
  WriteVarint(1);
end;

procedure TProtobufEncoder.WriteMessageField(FieldNumber: Integer; SubEncoder: TProtobufEncoder);
var
  Buf: TBytes;
begin
  if SubEncoder.Size = 0 then Exit;
  WriteTag(FieldNumber, WIRE_DELIMITED);
  Buf := SubEncoder.GetBytes;
  WriteVarint(QWord(Length(Buf)));
  FStream.WriteBuffer(Buf[0], Length(Buf));
end;

procedure TProtobufEncoder.WritePackedInt32Field(FieldNumber: Integer; const Values: array of Integer);
var
  TmpStream: TMemoryStream;
  I: Integer;
  B: Byte;
  V: QWord;
  Buf: TBytes;
begin
  if Length(Values) = 0 then Exit;

  TmpStream := TMemoryStream.Create;
  try
    for I := 0 to High(Values) do
    begin
      if Values[I] < 0 then
        V := QWord(Int64(Values[I]) and $FFFFFFFFFFFFFFFF)
      else
        V := QWord(Values[I]);
      while V > $7F do
      begin
        B := Byte(V and $7F) or $80;
        TmpStream.WriteBuffer(B, 1);
        V := V shr 7;
      end;
      B := Byte(V);
      TmpStream.WriteBuffer(B, 1);
    end;

    WriteTag(FieldNumber, WIRE_DELIMITED);
    WriteVarint(QWord(TmpStream.Size));
    SetLength(Buf, TmpStream.Size);
    TmpStream.Position := 0;
    TmpStream.ReadBuffer(Buf[0], TmpStream.Size);
    FStream.WriteBuffer(Buf[0], Length(Buf));
  finally
    TmpStream.Free;
  end;
end;

procedure TProtobufEncoder.WriteRepeatedMessageField(FieldNumber: Integer; const Encoders: array of TProtobufEncoder);
var
  I: Integer;
  Buf: TBytes;
begin
  for I := 0 to High(Encoders) do
  begin
    if Encoders[I].Size = 0 then Continue;
    WriteTag(FieldNumber, WIRE_DELIMITED);
    Buf := Encoders[I].GetBytes;
    WriteVarint(QWord(Length(Buf)));
    FStream.WriteBuffer(Buf[0], Length(Buf));
  end;
end;

procedure TProtobufEncoder.WriteRepeatedStringField(FieldNumber: Integer; Strings: TStringList);
var
  I: Integer;
begin
  if (Strings = nil) or (Strings.Count = 0) then Exit;
  for I := 0 to Strings.Count - 1 do
    WriteStringField(FieldNumber, Strings[I]);
end;

{ Encode methods }

procedure TProtobufEncoder.EncodeToolInfo(const Info: TScipToolInfo);
begin
  WriteStringField(FIELD_TOOL_NAME, Info.Name);
  WriteStringField(FIELD_TOOL_VERSION, Info.Version);
  WriteRepeatedStringField(FIELD_TOOL_ARGUMENTS, Info.Arguments);
end;

procedure TProtobufEncoder.EncodeMetadata(const Meta: TScipMetadata);
var
  ToolEnc: TProtobufEncoder;
begin
  WriteInt32Field(FIELD_META_VERSION, Meta.Version);

  ToolEnc := TProtobufEncoder.Create;
  try
    ToolEnc.EncodeToolInfo(Meta.ToolInfo);
    WriteMessageField(FIELD_META_TOOL_INFO, ToolEnc);
  finally
    ToolEnc.Free;
  end;

  WriteStringField(FIELD_META_PROJECT_ROOT, Meta.ProjectRoot);
  WriteInt32Field(FIELD_META_TEXT_ENCODING, Meta.TextDocumentEncoding);
end;

procedure TProtobufEncoder.EncodeRelationship(const Rel: TScipRelationship);
begin
  WriteStringField(FIELD_REL_SYMBOL, Rel.Symbol);
  WriteBoolField(FIELD_REL_IS_REFERENCE, Rel.IsReference);
  WriteBoolField(FIELD_REL_IS_IMPLEMENTATION, Rel.IsImplementation);
  WriteBoolField(FIELD_REL_IS_TYPE_DEFINITION, Rel.IsTypeDefinition);
  WriteBoolField(FIELD_REL_IS_DEFINITION, Rel.IsDefinition);
end;

procedure TProtobufEncoder.EncodeOccurrence(const Occ: TScipOccurrence);
var
  RangeVals: array of Integer;
begin
  { Range: 3 elements if same line, 4 if multiline }
  if Occ.Range.StartLine = Occ.Range.EndLine then
  begin
    SetLength(RangeVals, 3);
    RangeVals[0] := Occ.Range.StartLine;
    RangeVals[1] := Occ.Range.StartCol;
    RangeVals[2] := Occ.Range.EndCol;
  end
  else
  begin
    SetLength(RangeVals, 4);
    RangeVals[0] := Occ.Range.StartLine;
    RangeVals[1] := Occ.Range.StartCol;
    RangeVals[2] := Occ.Range.EndLine;
    RangeVals[3] := Occ.Range.EndCol;
  end;
  WritePackedInt32Field(FIELD_OCC_RANGE, RangeVals);

  WriteStringField(FIELD_OCC_SYMBOL, Occ.Symbol);
  WriteInt32Field(FIELD_OCC_SYMBOL_ROLES, Occ.SymbolRoles);

  if Occ.HasEnclosingRange then
  begin
    SetLength(RangeVals, 4);
    RangeVals[0] := Occ.EnclosingRange.StartLine;
    RangeVals[1] := Occ.EnclosingRange.StartCol;
    RangeVals[2] := Occ.EnclosingRange.EndLine;
    RangeVals[3] := Occ.EnclosingRange.EndCol;
    WritePackedInt32Field(FIELD_OCC_ENCLOSING_RANGE, RangeVals);
  end;
end;

procedure TProtobufEncoder.EncodeSymbolInfo(const Sym: TScipSymbolInfo);
var
  I: Integer;
  RelEncoders: array of TProtobufEncoder;
begin
  WriteStringField(FIELD_SYM_SYMBOL, Sym.Symbol);
  WriteRepeatedStringField(FIELD_SYM_DOCUMENTATION, Sym.Documentation);

  if Length(Sym.Relationships) > 0 then
  begin
    SetLength(RelEncoders, Length(Sym.Relationships));
    for I := 0 to High(Sym.Relationships) do
    begin
      RelEncoders[I] := TProtobufEncoder.Create;
      RelEncoders[I].EncodeRelationship(Sym.Relationships[I]);
    end;
    try
      WriteRepeatedMessageField(FIELD_SYM_RELATIONSHIPS, RelEncoders);
    finally
      for I := 0 to High(RelEncoders) do
        RelEncoders[I].Free;
    end;
  end;

  WriteInt32Field(FIELD_SYM_KIND, Sym.Kind);
  WriteStringField(FIELD_SYM_DISPLAY_NAME, Sym.DisplayName);
  WriteStringField(FIELD_SYM_ENCLOSING_SYMBOL, Sym.EnclosingSymbol);
end;

procedure TProtobufEncoder.EncodeDocument(const Doc: TScipDocument);
var
  I: Integer;
  OccEncoders, SymEncoders: array of TProtobufEncoder;
begin
  WriteStringField(FIELD_DOC_RELATIVE_PATH, Doc.RelativePath);

  if Length(Doc.Occurrences) > 0 then
  begin
    SetLength(OccEncoders, Length(Doc.Occurrences));
    for I := 0 to High(Doc.Occurrences) do
    begin
      OccEncoders[I] := TProtobufEncoder.Create;
      OccEncoders[I].EncodeOccurrence(Doc.Occurrences[I]);
    end;
    try
      WriteRepeatedMessageField(FIELD_DOC_OCCURRENCES, OccEncoders);
    finally
      for I := 0 to High(OccEncoders) do
        OccEncoders[I].Free;
    end;
  end;

  if Length(Doc.Symbols) > 0 then
  begin
    SetLength(SymEncoders, Length(Doc.Symbols));
    for I := 0 to High(Doc.Symbols) do
    begin
      SymEncoders[I] := TProtobufEncoder.Create;
      SymEncoders[I].EncodeSymbolInfo(Doc.Symbols[I]);
    end;
    try
      WriteRepeatedMessageField(FIELD_DOC_SYMBOLS, SymEncoders);
    finally
      for I := 0 to High(SymEncoders) do
        SymEncoders[I].Free;
    end;
  end;

  WriteStringField(FIELD_DOC_LANGUAGE, Doc.Language);
end;

procedure TProtobufEncoder.EncodeIndex(const Idx: TScipIndex);
var
  MetaEnc: TProtobufEncoder;
  I: Integer;
  DocEncoders: array of TProtobufEncoder;
begin
  MetaEnc := TProtobufEncoder.Create;
  try
    MetaEnc.EncodeMetadata(Idx.Metadata);
    WriteMessageField(FIELD_INDEX_METADATA, MetaEnc);
  finally
    MetaEnc.Free;
  end;

  if Length(Idx.Documents) > 0 then
  begin
    SetLength(DocEncoders, Length(Idx.Documents));
    for I := 0 to High(Idx.Documents) do
    begin
      DocEncoders[I] := TProtobufEncoder.Create;
      DocEncoders[I].EncodeDocument(Idx.Documents[I]);
    end;
    try
      WriteRepeatedMessageField(FIELD_INDEX_DOCUMENTS, DocEncoders);
    finally
      for I := 0 to High(DocEncoders) do
        DocEncoders[I].Free;
    end;
  end;
end;

procedure WriteScipIndex(const Idx: TScipIndex; const OutputPath: string);
var
  Enc: TProtobufEncoder;
  Buf: TBytes;
  F: TFileStream;
begin
  Enc := TProtobufEncoder.Create;
  try
    Enc.EncodeIndex(Idx);
    Buf := Enc.GetBytes;

    F := TFileStream.Create(OutputPath, fmCreate);
    try
      if Length(Buf) > 0 then
        F.WriteBuffer(Buf[0], Length(Buf));
    finally
      F.Free;
    end;
  finally
    Enc.Free;
  end;
end;

end.
