/*!
 * Copyright (C) Microsoft Corporation. All rights reserved.
 * This file is auto-generated. Do not modify it manually.
 * Changes to this file may be overwritten.
 */

export const dataSourcesInfo = {
  "OpenFoodFacts": {
    "tableId": "",
    "version": "",
    "dataSourceType": "Connector",
    "apis": {
      "GetProductByBarcode": {
        "path": "/product/{barcode}.json",
        "method": "GET",
        "parameters": [
          {
            "name": "barcode",
            "in": "path",
            "required": true,
            "type": "string"
          }
        ]
      }
    }
  },
  "almlab_5fopen_20food_20facts_5f7e995f9432ef978d": {
    "tableId": "",
    "version": "",
    "primaryKey": "",
    "dataSourceType": "Connector",
    "apis": {
      "GetProductByBarcode": {
        "path": "/{connectionId}/product/{barcode}.json",
        "method": "GET",
        "parameters": [
          {
            "name": "connectionId",
            "in": "path",
            "required": true,
            "type": "string"
          },
          {
            "name": "barcode",
            "in": "path",
            "required": true,
            "type": "string"
          }
        ],
        "responseInfo": {
          "200": {
            "type": "object"
          }
        }
      },
      "GetProductImage": {
        "path": "/{connectionId}/product-image",
        "method": "GET",
        "parameters": [
          {
            "name": "connectionId",
            "in": "path",
            "required": true,
            "type": "string"
          },
          {
            "name": "imageUrl",
            "in": "query",
            "required": true,
            "type": "string"
          }
        ],
        "responseInfo": {
          "200": {
            "type": "file"
          }
        }
      }
    }
  },
  "almlab_products": {
    "tableId": "",
    "version": "",
    "primaryKey": "almlab_productid",
    "dataSourceType": "Dataverse",
    "apis": {}
  },
  "almlab_warehouseitems": {
    "tableId": "",
    "version": "",
    "primaryKey": "almlab_warehouseitemid",
    "dataSourceType": "Dataverse",
    "apis": {}
  },
  "almlab_warehouselocations": {
    "tableId": "",
    "version": "",
    "primaryKey": "almlab_warehouselocationid",
    "dataSourceType": "Dataverse",
    "apis": {}
  },
  "almlab_warehousetransactions": {
    "tableId": "",
    "version": "",
    "primaryKey": "almlab_warehousetransactionid",
    "dataSourceType": "Dataverse",
    "apis": {}
  }
};
