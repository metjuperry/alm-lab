using System.Text.Json;
using Microsoft.Playwright;
using Tests.UI.Authentication;
using Tests.UI.Support;

namespace Tests.UI.StepDefinitions;

public sealed class GroceryFixture
{
    public string Id { get; }
    public string Name { get; }

    private GroceryFixture(string id, string name) { Id = id; Name = name; }

    private static async Task<IPage> OpenApiAsync(IBrowserContext context)
    {
        var page = await context.NewPageAsync();
        await page.GotoAsync($"{TestConfiguration.EnvironmentUrl.TrimEnd('/')}/main.aspx?appname={Uri.EscapeDataString(TestConfiguration.AppName)}");
        await page.WaitForFunctionAsync("() => !!window.Xrm?.WebApi?.createRecord");
        return page;
    }

    public static async Task<GroceryFixture> CreateAsync(IBrowserContext context, string label)
    {
        var name = $"BDD-{Guid.NewGuid():N} {label}";
        var page = await OpenApiAsync(context);
        try
        {
            var id = await page.EvaluateAsync<string>("""
                async name => (await Xrm.WebApi.createRecord("__PREFIX___warehouseitem", {
                    "__PREFIX___name": name,
                    "__PREFIX___sku": name.substring(0, 36),
                    "__PREFIX___availablequantity": 0,
                    "__PREFIX___category": 100000002
                })).id
                """, name);
            return new GroceryFixture(id, name);
        }
        finally { await page.CloseAsync(); }
    }

    public async Task SeedAsync(IBrowserContext context, int quantity)
    {
        var page = await OpenApiAsync(context);
        try
        {
            await page.EvaluateAsync("""
                async args => {
                    await Xrm.WebApi.createRecord("__PREFIX___warehousetransaction", {
                        "__PREFIX___name": "BDD opening balance",
                        "__PREFIX___quantity": args.quantity,
                        "__PREFIX___transactiontype": 100000000,
                        "__PREFIX___transactiondate": new Date().toISOString(),
                        "__PREFIX___itemid@odata.bind": `/__PREFIX___warehouseitems(${args.id})`
                    });
                }
                """, new { id = Id, quantity });
        }
        finally { await page.CloseAsync(); }
    }

    public async Task<JsonElement> ReadStateAsync(IBrowserContext context)
    {
        var page = await OpenApiAsync(context);
        try
        {
            return await page.EvaluateAsync<JsonElement>("""
                async id => {
                    const item = await Xrm.WebApi.retrieveRecord("__PREFIX___warehouseitem", id, "?$select=__PREFIX___availablequantity");
                    const movements = await Xrm.WebApi.retrieveMultipleRecords("__PREFIX___warehousetransaction",
                        `?$select=__PREFIX___warehousetransactionid&$filter=___PREFIX___itemid_value eq ${id}`);
                    return { quantity: item.__PREFIX___availablequantity, movements: movements.entities.length };
                }
                """, Id);
        }
        finally { await page.CloseAsync(); }
    }

    public async Task DeleteAsync(IBrowser browser)
    {
        await using var context = await SignIn.CreateSignedInContextAsync(browser, "a warehouse manager");
        var page = await OpenApiAsync(context);
        // Only this scenario's item and its movements are selected. Deleting outbound
        // movements first restores the inbound stock before those opening balances go away.
        var records = await page.EvaluateAsync<JsonElement>("""
            async id => (await Xrm.WebApi.retrieveMultipleRecords("__PREFIX___warehousetransaction",
                `?$select=__PREFIX___warehousetransactionid,__PREFIX___transactiontype&$filter=___PREFIX___itemid_value eq ${id}`)).entities
            """, Id);
        foreach (var record in records.EnumerateArray().OrderByDescending(x => x.GetProperty("__PREFIX___transactiontype").GetInt32()))
        {
            var id = record.GetProperty("__PREFIX___warehousetransactionid").GetString();
            await page.EvaluateAsync("id => Xrm.WebApi.deleteRecord('__PREFIX___warehousetransaction', id)", id);
        }
        await page.EvaluateAsync("id => Xrm.WebApi.deleteRecord('__PREFIX___warehouseitem', id)", Id);
    }
}
