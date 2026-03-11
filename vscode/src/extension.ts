import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let outputChannel: vscode.OutputChannel;

export async function activate(
  context: vscode.ExtensionContext
): Promise<void> {
  outputChannel = vscode.window.createOutputChannel("Sorbet View");

  await startClient();

  context.subscriptions.push(
    vscode.commands.registerCommand("sorbetView.restart", async () => {
      outputChannel.appendLine("Restarting Sorbet View server...");
      if (client) {
        await client.restart();
      } else {
        await startClient();
      }
      outputChannel.appendLine("Sorbet View server restarted.");
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (e.affectsConfiguration("sorbetView.command")) {
        outputChannel.appendLine("Configuration changed, restarting server...");
        if (client) {
          await client.stop();
          client = undefined;
        }
        await startClient();
      }
    })
  );
}

async function startClient(): Promise<void> {
  const config = vscode.workspace.getConfiguration("sorbetView");
  const commandLine = config.get<string>("command") || "bundle exec sv lsp";
  const parts = commandLine.split(/\s+/);
  const command = parts[0];
  const args = parts.slice(1);

  outputChannel.appendLine(`Starting: ${commandLine}`);

  const serverOptions: ServerOptions = {
    command,
    args,
    options: { env: { ...process.env }, shell: true },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "erb" },
      { scheme: "file", language: "ruby" },
    ],
    outputChannel,
  };

  client = new LanguageClient(
    "sorbetView",
    "Sorbet View",
    serverOptions,
    clientOptions
  );

  try {
    await client.start();
    outputChannel.appendLine("Sorbet View server started.");
  } catch (error) {
    outputChannel.appendLine(`Failed to start server: ${error}`);
    client = undefined;
  }
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
    client = undefined;
  }
}
