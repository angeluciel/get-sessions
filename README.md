# Get Sessions - Sessões do Veeam

Esse é um script em **PowerShell 7** para consultar o histórico de execuções pela API REST do Veeam Backup & Replication, filtrar sessões de backup, cópia de backup e restauração e gerar relatórios JSON e CSV.

O projeto foi desenvolvido para facilitar a consulta e a análise de execuções em um período específico, incluindo tentativas de repetição (retries).
**Ele não executa backups nem restaurações**.

## Funcionalidades
* Consulta as sessões de API REST com paginação.
* Seleciona sessões de backup, backup copy e restauração criadas no período informado.
* Mantém os dados originais das execuções na seção `all-executions`.
* Produz uma visão client-ready na seção `beautified`, agrupando tentativas quando existe vínculo pelo campo `originalSessionId`.
* Mantém execuções sem vínculo conehcido separadas.
* Exporta um relatório JSON e uma planilha CSV delimitada por `;`.
* Registra logs de execução e erros.

> [!IMPORTANT]
> O filtro de datas considera o horário de **criação da sessão**, e não o momento em que ela terminou.
> **As datas são interpretadas no fuso horário do computador que executa o script**.

## Pré-Requisitos
* PowerShell 7.0 ou superior (`pwsh`)
* Acesso de rede à API REST do Veeam Backup & Replication
* Usuário do Veeam autorizado a autenticar na API e consultar o histórico de sessões.
* Módulos PowerShell:
 * Microsoft.PowerShell.SecretManagement
 * Microsoft.PowerShell.SecretStore
* Git, caso deseje clonar o repositório

## Instação
Abra o PowerShell 7 e execute:
```powershell
git clone https://github.com/angeluciel/get-sessions.git
cd get-sessions

Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

Se os módulos já estiverem instalados, não é necessário instalá-los novamente.

## Configuração do cofre de credenciais
A autenticação utiliza o **SecretStore**, com dois segredos de nomes fixos:

| Nome do Segredo    | Conteúdo                     |
| ------------------ | ---------------------------- |
| `VeeamApiUser`     | Nome do usuário de API Veeam |
| `VeeamApiPassword` | Senha desse usuario          |

O arquivo XML criado nesta etapa guarda a senha usada para desbloquear o SecretStore, não o token de acesso da API. Nunca o inclua no repositório.

###  1. Registrar o SecretStore e proteger sua senha
Execute os comandos com a **mesma conta windows** que executará o script: 

```powershell
# Diretório privado fora do repositório
$secretsDir = Join-Path $HOME '.get-sessions'
New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
$credentialPath = Join-Path $secretsDir 'secretstore-password.xml'

# Defina uma senha forte para o SecretStore
$storePassword = Read-Host 'Senha do SecretStore' -AsSecureString
$storePassword | Export-Clixml -Path $credentialPath

# Registre o cofre como padrão
Register-SecretVault -Name LocalStore `
    -ModuleName Microsoft.PowerShell.SecretStore `
    -DefaultVault

# Exija senha, mas não abra prompts durante a automação
Set-SecretStoreConfiguration `
    -Authentication Password `
    -Interaction None `
    -Password $storePassword `
    -Confirm:$false

Unlock-SecretStore -Password $storePassword
```

>[!NOTE]
> Se o SecretStore já estiver configurado, reutilize o cofre e a senha existentes. Não recrie sua configuração sem verificar o impacto sobre os segredos armazenados. Se LocalStore já estiver registrado, não execute Register-SecretVault novamente.

### 2. Salvar as credenciais do Veeam

```Powershell
Set-Secret -Name VeeamApiUser `
    -Secret (Read-Host 'Usuário da API Veeam')

Set-Secret -Name VeeamApiPassword `
    -Secret (Read-Host 'Senha da API Veeam' -AsSecureString)

# Confirme apenas a existência dos segredos, sem exibir seus valores
Get-SecretInfo
```

## Configuração do projeto

Na raiz do repositório, crie o arquivo local `config.psd1`:
```powershell
Copy-Item ./config.example.psd1 ./config.psd1
```

# Execução
Execute o seguinte comando a partir da raíz do repositório:
```powershell
pwsh -NoProfile -File ./functions/main.ps1
```

Para indicar outro arquivo de configuração:
```powershell
pwsh -NoProfile -File ./functions/main.ps1 -ConfigPath ./config.psd1
```

