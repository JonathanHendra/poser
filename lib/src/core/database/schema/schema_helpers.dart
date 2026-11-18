String scopedTable(String name, List<String> columns) =>
    'CREATE TABLE $name (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id TEXT NOT NULL REFERENCES businesses(owner_id), ${columns.join(', ')}, UNIQUE(owner_id, id))';
String reference(String column, String table) =>
    'FOREIGN KEY(owner_id, $column) REFERENCES $table(owner_id, id)';
String amount(String name, {bool signed = false}) =>
    '$name INTEGER NOT NULL DEFAULT 0 CHECK(typeof($name) = \'integer\' AND $name BETWEEN ${signed ? '-9007199254740991' : '0'} AND 9007199254740991)';
List<String> fraction(
  String prefix, {
  bool signed = false,
  bool positive = false,
}) => [
  '${prefix}_num INTEGER NOT NULL DEFAULT ${positive ? 1 : 0} CHECK(typeof(${prefix}_num) = \'integer\' AND ${prefix}_num BETWEEN ${signed
      ? '-9007199254740991'
      : positive
      ? '1'
      : '0'} AND 9007199254740991)',
  '${prefix}_den INTEGER NOT NULL DEFAULT 1 CHECK(typeof(${prefix}_den) = \'integer\' AND ${prefix}_den BETWEEN 1 AND 9007199254740991)',
];

const movementTypes =
    "'initial','purchase','sale','sale_return','purchase_return','adjustment_in','adjustment_out','transfer_in','transfer_out','bundle_consumption','damage','loss','stock_opname'";
