local fmt = string.format
local type = type
local assert = assert
local pairs = pairs
module(...)

local createIndexSql = [[ 
CREATE TABLE IF NOT EXISTS %s (
    entity_id VARCHAR(32) NOT NULL UNIQUE,
    %s VARCHAR(512) NOT NULL, 
    PRIMARY KEY(%s, entity_id)
) ENGINE=InnoDB; ]]

local dropIndexSql = [[
DROP TABLE %s;
]]

local deleteIndexSql = [[
]]

local findIndexSql = [[
SELECT entity_id FROM %s WHERE %s = '%s';
]]

local insertIndexSql = [[
INSERT INTO %s (%s,%s) VALUES (%s,%s);
]]

function createIndex(property)
    local tableName = property.."_index"
    local sql = fmt(createIndexSql, tableName, property, property)

    return sql
end

function dropIndex(property) 
    local tableName = property .. "_index"
    local sql = fmt(dropIndexSql, tableName) 

    return sql
end

function findIndex(propertyTbl) 
    assert(type(propertyTbl) == "table", "param in FindIdSql() is NOT a table.")

    local n = pairs(propertyTbl)
    local k, v = n(propertyTbl) 
    local tableName = k .. "_index"
    local sql = fmt(findIndexSql, tableName, k, v)

    return sql
end

function insertIndex(property, id, value)
    local tableName = property .. "_index"
    local sql = fmt(insertIndexSql, tableName, "entity_id", property, id, value) 

    return sql
end
