terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}

data "local_file" "openapi" {
  filename = "../openapi/inference.json"
}

resource "azurerm_api_management_api" "api" {
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  revision           = 1
  name               = "tfm-OpenAI"
  display_name       = "Terraform Managed OpenAI"
  path               = "tfm/openai"
  protocols          = ["https"]
  import {
    content_format = "openapi"
    content_value  = data.local_file.openapi.content
  }
 
}

resource azurerm_api_management_api_policy "policy" {
  api_name            = azurerm_api_management_api.api.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name

  xml_content         = <<XML
<policies>
    <inbound>
        <base />
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
        </set-header>
        <set-backend-service backend-id="openaibackendpool" />
        <set-variable name="counter" value="@{return 0;}" />
    </inbound>
    <backend>
        <retry condition="@(context.Response.StatusCode > 400)" count="4" interval="1" max-interval="45" delta="1" first-fast-retry="false">
            <set-variable name="counter" value="@{return (context.Variables.GetValueOrDefault<int>("counter") + 1);}" />
            <forward-request buffer-response="false" buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <base />
        <set-header name="X-Counter" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<int>("counter") + "")</value>
        </set-header>
    </outbound>
</policies>
XML

}

resource "azapi_resource" "backend1" {
  type = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name = "openaibackend1"
  parent_id = var.apim_id
  body = {
    properties = {
        circuitBreaker = {
            rules = [
                {
                    acceptRetryAfter = true
                    failureCondition = {
                        count = 1
                        errorReasons = [
                            "Server errors"
                        ]
                        interval = "PT1M"
                        statusCodeRanges = [
                            {
                                max = 599
                                min = 429
                            }
                        ]
                    }
                    name = "myCircuitBreaker"
                    tripDuration = "PT1M"
                }
            ]
        }
        type = "Single"
        url = var.backend1url
        protocol = "http"
    }
  }
}

resource "azapi_resource" "backend2" {
  type = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name = "openaibackend2"
  parent_id = var.apim_id
  body = {
    properties = {
        circuitBreaker = {
            rules = [
                {
                    acceptRetryAfter = true
                    failureCondition = {
                        count = 1
                        errorReasons = [
                            "Server errors"
                        ]
                        interval = "PT1M"
                        statusCodeRanges = [
                            {
                                max = 599
                                min = 429
                            }
                        ]
                    }
                    name = "myCircuitBreaker"
                    tripDuration = "PT1M"
                }
            ]
        }
        type = "Single"
        url = var.backend2url
        protocol = "http"
    }
  }
}

resource "azapi_resource" "backendpool" {
  type = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name = "openaibackendpool"
  parent_id = var.apim_id
  body = {
    properties = {
        pool = {
            services = [
                {
                    id = azapi_resource.backend1.id
                    priority = 1
                    weight = 1
                },
                {
                    id = azapi_resource.backend2.id
                    priority = 2
                    weight = 1
                }
            ]
        }
        type = "Pool"
    }
  }
  schema_validation_enabled = false
}