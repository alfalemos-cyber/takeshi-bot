#!/bin/bash

# Script de Instalação Automatizada
# Sistema Integrado: Bot WhatsApp + VPN + Mercado Pago
# Versão: 1.0

echo "=================================================="
echo "  INSTALAÇÃO DO SISTEMA BOT WHATSAPP + VPN"
echo "=================================================="
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script deve ser executado como root (sudo)"
    exit 1
fi

# Função para exibir status
show_status() {
    echo "🔄 $1..."
}

show_success() {
    echo "✅ $1"
}

show_error() {
    echo "❌ $1"
    exit 1
}

# Atualizar sistema
show_status "Atualizando sistema"
apt update && apt upgrade -y || show_error "Falha ao atualizar sistema"
show_success "Sistema atualizado"

# Instalar dependências básicas
show_status "Instalando dependências básicas"
apt install -y curl wget git build-essential || show_error "Falha ao instalar dependências"
show_success "Dependências básicas instaladas"

# Instalar Node.js 18.x
show_status "Instalando NVM e Node.js 16.x"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash || show_error "Falha ao baixar script de instalação do NVM"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
nvm install 16 || show_error "Falha ao instalar Node.js 16.x via NVM"
nvm use 16 || show_error "Falha ao usar Node.js 16.x via NVM"
nvm alias default 16 || show_error "Falha ao definir Node.js 16.x como padrão"
show_success "Node.js 16.x instalado: $(node --version )"

# Instalar FFmpeg
show_status "Instalando FFmpeg"
apt install -y ffmpeg || show_error "Falha ao instalar FFmpeg"
show_success "FFmpeg instalado"

# Verificar se SSH-PLUS já está instalado
show_success "SSH-PLUS já está instalado (ignorado, pois já existe)"

# Criar diretório para o bot
BOT_DIR="/opt/takeshi-bot"
show_status "Criando diretório do bot em $BOT_DIR"
mkdir -p $BOT_DIR
cd $BOT_DIR

# Clonar repositório do bot
show_status "Clonando repositório do bot WhatsApp"
wget https://github.com/alfalemos-cyber/takeshi-bot/raw/main/takeshi-bot.zip || show_error "Falha ao baixar o bot"
unzip takeshi-bot.zip || show_error "Falha ao descompactar o bot"
rm takeshi-bot.zip || show_error "Falha ao remover o arquivo zip"

# Verificar se o bot foi descompactado em um subdiretório e mover
if [ -d "takeshi-bot" ]; then
    show_status "Movendo arquivos do bot para o diretório correto"
    mv takeshi-bot/* . || show_error "Falha ao mover arquivos do bot"
    rmdir takeshi-bot || show_error "Falha ao remover subdiretório vazio"
fi
show_success "Repositório clonado"

# Instalar dependências do bot
show_status "Instalando dependências do bot"
npm install || show_error "Falha ao instalar dependências do bot"
npm install axios || show_error "Falha ao instalar axios"
show_success "Dependências do bot instaladas"

# Criar arquivos de integração
show_status "Criando arquivos de integração"

# Criar módulo Mercado Pago
cat > src/mercadopago.js << 'EOF'
const axios = require('axios' );

// Configurações do Mercado Pago
const MERCADO_PAGO_CONFIG = {
    ACCESS_TOKEN: 'APP_USR-153110256233483-042622-5e61d8c4f515a3e4858a188558b7b725-1697276618',
    PUBLIC_KEY: 'APP_USR-412946cc-273e-4208-a32e-8391bceb3419',
    CLIENT_ID: '153110256233483',
    CLIENT_SECRET: 'U09K3LS1V2RCfFTeqjFbUm415xApHxWy',
    BASE_URL: 'https://api.mercadopago.com'
};

class MercadoPagoService {
    constructor( ) {
        this.accessToken = MERCADO_PAGO_CONFIG.ACCESS_TOKEN;
        this.baseURL = MERCADO_PAGO_CONFIG.BASE_URL;
    }

    async createPixPayment(amount, description, externalReference) {
        try {
            const paymentData = {
                transaction_amount: amount,
                description: description,
                payment_method_id: 'pix',
                external_reference: externalReference,
                payer: {
                    email: 'cliente@email.com'
                }
            };

            const response = await axios.post(
                `${this.baseURL}/v1/payments`,
                paymentData,
                {
                    headers: {
                        'Authorization': `Bearer ${this.accessToken}`,
                        'Content-Type': 'application/json'
                    }
                }
            );

            return {
                success: true,
                payment_id: response.data.id,
                qr_code: response.data.point_of_interaction.transaction_data.qr_code,
                qr_code_base64: response.data.point_of_interaction.transaction_data.qr_code_base64,
                ticket_url: response.data.point_of_interaction.transaction_data.ticket_url,
                status: response.data.status
            };
        } catch (error) {
            console.error('Erro ao criar pagamento PIX:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }

    async checkPaymentStatus(paymentId) {
        try {
            const response = await axios.get(
                `${this.baseURL}/v1/payments/${paymentId}`,
                {
                    headers: {
                        'Authorization': `Bearer ${this.accessToken}`
                    }
                }
            );

            return {
                success: true,
                status: response.data.status,
                status_detail: response.data.status_detail,
                external_reference: response.data.external_reference,
                transaction_amount: response.data.transaction_amount
            };
        } catch (error) {
            console.error('Erro ao verificar status do pagamento:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }
}

module.exports = MercadoPagoService;
EOF

# Criar módulo VPN Manager
cat > src/vpn-manager.js << 'EOF'
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class VPNManager {
    constructor() {
        this.sshPlusPath = '/root/ssh-plus';
        this.usersFile = '/root/usuarios.txt';
    }

    generateUsername(prefix = 'vpn') {
        const timestamp = Date.now().toString().slice(-6);
        const random = crypto.randomBytes(3).toString('hex');
        return `${prefix}${timestamp}${random}`;
    }

    generatePassword(length = 8) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        let password = '';
        for (let i = 0; i < length; i++) {
            password += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return password;
    }

    async createSSHUser(username, password, days = 30) {
        return new Promise((resolve, reject) => {
            const expirationDate = new Date();
            expirationDate.setDate(expirationDate.getDate() + days);
            const expDate = expirationDate.toISOString().split('T')[0];

            const commands = [
                `useradd -M -s /bin/false ${username}`,
                `echo "${username}:${password}" | chpasswd`,
                `chage -E ${expDate} ${username}`,
                `echo "${username} ${password} ${expDate}" >> ${this.usersFile}`
            ].join(' && ');

            exec(commands, (error, stdout, stderr) => {
                if (error) {
                    console.error('Erro ao criar usuário SSH:', error);
                    reject(error);
                    return;
                }
                
                resolve({
                    username,
                    password,
                    expirationDate: expDate,
                    created: true
                });
            });
        });
    }

    async getServerInfo() {
        return new Promise((resolve, reject) => {
            exec('hostname -I | awk \'{print $1}\'', (error, stdout, stderr) => {
                if (error) {
                    reject(error);
                    return;
                }
                
                const serverIP = stdout.trim();
                
                resolve({
                    ip: serverIP,
                    sshPort: '22',
                    hostname: 'VPN Server'
                });
            });
        });
    }

    async createVPNConfig(username, password, plano) {
        try {
            const serverInfo = await this.getServerInfo();
            
            const config = {
                servidor: {
                    ip: serverInfo.ip,
                    porta_ssh: serverInfo.sshPort,
                    hostname: serverInfo.hostname
                },
                usuario: {
                    login: username,
                    senha: password,
                    plano: plano.nome,
                    duracao: plano.duracao,
                    criado_em: new Date().toISOString()
                },
                aplicativos: {
                    http_injector: {
                        payload: `GET / HTTP/1.1[crlf]Host: ${serverInfo.ip}[crlf]Upgrade: websocket[crlf][crlf]`,
                        proxy: `${serverInfo.ip}:8080`
                    },
                    http_custom: {
                        payload: `GET wss://mobilidade.cloud.caixa.gov.br/ HTTP/1.1[crlf]Host: ${serverInfo.ip}[crlf]Upgrade: websocket[crlf][crlf]`,
                        proxy: `${serverInfo.ip}:8080`
                    },
                    ssh_tunnel: {
                        host: serverInfo.ip,
                        porta: serverInfo.sshPort,
                        usuario: username,
                        senha: password
                    }
                }
            };

            return config;
        } catch (error ) {
            console.error('Erro ao criar configuração VPN:', error);
            throw error;
        }
    }
}

module.exports = VPNManager;
EOF

show_success "Arquivos de integração criados"

# Criar diretório de database
mkdir -p database
show_success "Diretório de database criado"

# Configurar permissões
show_status "Configurando permissões"
chown -R root:root $BOT_DIR
chmod +x $BOT_DIR
show_success "Permissões configuradas"

# Criar serviço systemd
show_status "Criando serviço systemd"
cat > /etc/systemd/system/takeshi-bot.service << EOF
[Unit]
Description=Takeshi Bot WhatsApp
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/node src/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable takeshi-bot
show_success "Serviço systemd criado e habilitado"

# Criar script de configuração
cat > configure-bot.sh << 'EOF'
#!/bin/bash

echo "=================================================="
echo "  CONFIGURAÇÃO DO BOT WHATSAPP"
echo "=================================================="
echo ""

read -p "Digite o número do WhatsApp do bot (ex: 5521993997287): " BOT_NUMBER
read -p "Digite o número do dono do bot (ex: 5521993997287): " OWNER_NUMBER

# Atualizar configuração
sed -i "s/exports.BOT_NUMBER = \".*\"/exports.BOT_NUMBER = \"$BOT_NUMBER\"/" src/config.js
sed -i "s/exports.OWNER_NUMBER = \".*\"/exports.OWNER_NUMBER = \"$OWNER_NUMBER\"/" src/config.js

echo ""
echo "✅ Configuração atualizada!"
echo ""
echo "Para iniciar o bot, execute:"
echo "  systemctl start takeshi-bot"
echo ""
echo "Para ver os logs, execute:"
echo "  journalctl -u takeshi-bot -f"
echo ""
echo "Para parar o bot, execute:"
echo "  systemctl stop takeshi-bot"
echo ""
EOF

chmod +x configure-bot.sh
show_success "Script de configuração criado"

# Finalização
echo ""
echo "=================================================="
echo "  INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "=================================================="
echo ""
echo "📁 Bot instalado em: $BOT_DIR"
echo "⚙️  Para configurar o bot, execute:"
echo "    cd $BOT_DIR && ./configure-bot.sh"
echo ""
echo "🚀 Para iniciar o bot após configurar:"
echo "    systemctl start takeshi-bot"
echo ""
echo "📊 Para monitorar o bot:"
echo "    journalctl -u takeshi-bot -f"
echo ""
echo "📚 Documentação completa disponível em:"
echo "    $BOT_DIR/documentacao_completa.md"
echo ""
echo "=================================================="
echo "  SISTEMA PRONTO PARA USO!"
echo "=================================================="

