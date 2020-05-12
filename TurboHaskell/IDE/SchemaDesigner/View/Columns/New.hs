module TurboHaskell.IDE.SchemaDesigner.View.Columns.New where

import TurboHaskell.ViewPrelude
import TurboHaskell.IDE.SchemaDesigner.Types
import TurboHaskell.IDE.ToolServer.Types
import TurboHaskell.IDE.ToolServer.Layout
import TurboHaskell.View.Modal
import TurboHaskell.IDE.SchemaDesigner.View.Layout

data NewColumnView = NewColumnView
    { statements :: [Statement]
    , tableName :: Text
    , generatedHaskellCode :: Text
    , primaryKeyExists :: Bool
    }

instance View NewColumnView ViewContext where
    html NewColumnView { .. } = [hsx|
        {visualNav}
        <div class="container">
            <form class="w-100 d-flex justify-content-end" action={pathTo PushToDbAction}>
                <button type="submit" class="btn btn-primary my-3">Push to DB</button>
            </form>
            <div class="row no-gutters bg-white">
                {renderObjectSelector (zip [0..] statements) (Just tableName)}
                {renderColumnSelector tableName  (zip [0..] columns) statements}
            </div>

            <pre class="generated-haskell-code"><code>{generatedHaskellCode}</code></pre>
        </div>
        {Just modal}
    |]
        where
            table = findTableByName tableName statements
            columns = maybe [] (get #columns) table

            modalContent = [hsx|
                <form method="POST" action={CreateColumnAction}>
                    <input type="hidden" name="tableName" value={tableName}/>

                    <div class="form-group row">
                        <label class="col-sm-2 col-form-label">Name:</label>
                        <div class="col-sm-10">
                            <input name="name" type="text" class="form-control" autofocus="autofocus"/>
                        </div>
                    </div>

                    <div class="form-group row">
                        <label class="col-sm-2 col-form-label">Type:</label>
                        <div class="col-sm-10">
                            <select id="typeSelector" name="columnType" class="form-control select2-simple">
                                <option value="TEXT">Text</option>
                                <option value="INT">Int</option>
                                <option value="UUID">UUID</option>
                                <option value="BOOLEAN">Bool</option>
                                <option value="TIMESTAMP WITH TIME ZONE">Timestamp</option>
                                <option value="REAL">Float</option>
                                <option value="DOUBLE PRECISION">Double</option>
                                <option value="POINT">Point</option>
                            </select>
                        </div>
                    </div>

                    <div class="form-group row">
                        {primaryKeyCheckbox}
                        <label class="col col-form-label">
                            <input type="checkbox" name="allowNull" class="mr-2"/>Allow Null
                        </label>
                        <label class="col col-form-label">
                            <input type="checkbox" name="isUnique" class="mr-2"/>Unique
                        </label>
                    </div>

                    <div class="form-group row">
                        <label class="col-sm-2 col-form-label">Default Value:</label>
                        {defaultSelector}
                        <div class="col-sm-2"></div>
                        <div class="col-sm-10">
                            <input style="display: none;" name="customDefaultValue" type="text" class="form-control"/>    
                        </div>
                    </div>

                    <div class="text-right">
                        <button type="submit" class="btn btn-primary">Create Column</button>
                    </div>

                    <input type="hidden" name="primaryKey" value={inputValue False}/>
                    <input type="hidden" name="allowNull" value={inputValue False}/>
                    <input type="hidden" name="isUnique" value={inputValue False}/>
                </form>
            |]
                where
                    primaryKeyCheckbox = if primaryKeyExists
                        then mempty
                        else [hsx|<label class="col col-form-label">
                            <input type="checkbox" name="primaryKey" class="mr-2"/>Primary Key
                        </label>|]
                    defaultSelector = preEscapedToHtml [plain|
                        <div class="col-sm-10">
                            <select id="defaultSelector" name="defaultValue" class="form-control select2">
                                <option value="NODEFAULT">no default</option>
                                <option value="EMPTY">''</option>
                                <option value="NULL">null</option>
                            </select>
                        </div>
                        <script>
                            $('.select2').select2({
                                placeholder: "Select a default value or type in a custom default value",
                                tags: true
                            });
                            $('.select2-simple').select2();
                            $('#typeSelector').change(function () {
                                switch (this.value) {
                                    case "UUID":
                                        $('#defaultSelector').empty()
                                        .append(new Option("uuid_generate_v4()", 'uuid_generate_v4()', true, true))
                                        .append(new Option("no default", "NODEFAULT", false, false))
                                        .append(new Option("''", "EMPTY", false, false))
                                        .append(new Option("null", "NULL", false, false))
                                        .trigger('change');
                                        break;
                                    case "TIMESTAMP WITH TIME ZONE":
                                        $('#defaultSelector').empty()
                                        .append(new Option("created at", 'NOW()', true, true))
                                        .append(new Option("no default", "NODEFAULT", false, false))
                                        .append(new Option("''", "EMPTY", false, false))
                                        .append(new Option("null", "NULL", false, false))
                                        .trigger('change');
                                        break;
                                    default:
                                        $('#defaultSelector').empty()
                                        .append(new Option("no default", "NODEFAULT", true, true))
                                        .append(new Option("''", "EMPTY", false, false))
                                        .append(new Option("null", "NULL", false, false))
                                        .trigger('change');
                                        break;
                                }
                            });
                        </script>
                    |]
            modalFooter = mempty 
            modalCloseUrl = pathTo ShowTableAction { tableName }
            modalTitle = "New Column"
            modal = Modal { modalContent, modalFooter, modalCloseUrl, modalTitle }