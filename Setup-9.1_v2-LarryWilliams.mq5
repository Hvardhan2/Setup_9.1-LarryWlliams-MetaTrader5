//+------------------------------------------------------------------+
//|                                                          9_1.mq5 |
//|                                                        DevTrader |
//|                                             medium.com/devtrader |
//|                              Setup 9.1 criado por Larry Williams |
//+------------------------------------------------------------------+
#property copyright "@DevTrader"
#property link      "medium.com/devtrader"
#property version   "1.0"

#include <Trade/SymbolInfo.mqh>

input ENUM_TIMEFRAMES      TimeFrame      = PERIOD_M5; // TimeFrame
input int                  Media          = 9;         // Média
input double               TP             = 1000;      // Take Profit em pontos
input int                  Volume         = 5;         // Quantidade Inicial de Contratos
input string               HoraInicial    = "09:00";   // Horário de Início para novas operações
input string               HoraFinal      = "16:00";   // Horário de Término para novas operações
input string               HoraFechamento = "17:30";   // Horário de Fechamento para posições abertas
input double               LimiteGain     = "1000";    // Limite de Gain diário financeiro
input double               LimiteLoss     = "500";     // Limite de Loss diário financeiro
input double               BE             = "500";     // Variação em pontos para ativar o break even da operação
input double               RP             = "500";     // Variação em pontos para fazer realização parcial
input int                  VolumeRP       = "3";       // Quantidade de contratos para realização parcial

// Identificador do EA
int magic_number = 1234; 

//Manipulador da media movel
int handle_media;

//Obtem informações do ativo
CSymbolInfo simbolo; 

//Classes para roteamento de ordens
MqlTradeRequest request;
MqlTradeResult result;
MqlTradeCheckResult check_result;

// Classes para controle de tempo
MqlDateTime hora_inicial, hora_final, hora_fechamento;

// Contagem para verificação de novo candle
static int bars;

//Estrutura para representar um sinal de compra ou venda
enum ENUM_SINAL {COMPRA = 1, VENDA  = -1, NULO   = 0};

//Armazena o sinal da última operação
ENUM_SINAL ultimo_sinal;

//Validação dos Inputs e inicialização do EA
int OnInit()
 {

   if(!simbolo.Name(_Symbol))
   {
      Print("Erro ao carregar o ativo.");
      return INIT_FAILED;
   }

   handle_media = iMA(_Symbol, TimeFrame, Media, 0, MODE_EMA, PRICE_CLOSE);
   
   if (handle_media < 0) 
   {
      Print("Erro ao inicializar a média móvel.");
      return INIT_FAILED;
   }
   
   if (Media < 0 || TP < 0 || BE < 0 || RP < 0 || VolumeRP < 0 || LimiteGain < 0 || LimiteLoss < 0)
   {
      Print("Parâmetros inválidos.");
      return INIT_FAILED;
   }

   // Inicialização das variáveis de tempo
   TimeToStruct(StringToTime(HoraInicial), hora_inicial);
   TimeToStruct(StringToTime(HoraFinal), hora_final);
   TimeToStruct(StringToTime(HoraFechamento), hora_fechamento);
   
   // Verificação de inconsistências nos parâmetros de entrada
   if( (hora_inicial.hour > hora_final.hour || (hora_inicial.hour == hora_final.hour && hora_inicial.min > hora_final.min))
         || hora_final.hour > hora_fechamento.hour || (hora_final.hour == hora_fechamento.hour && hora_final.min > hora_fechamento.min))
   {
      Print("Os horários fornecidos estão inválidos.");
      return INIT_FAILED;
   }
   
   ultimo_sinal = NULO;
   
   return(INIT_SUCCEEDED);
   
 }

//Evento invocado ao reiniciar o EA
void OnDeinit(const int reason)
 {
   printf("Reiniciando EA: %d", reason);
 }
  
//Evento invocado cada a novo tick do ativo
void OnTick()
  {

   //Atualiza os dados de cotação do ativo
   if(!simbolo.RefreshRates())
      return;
     
   //Verifica se um novo dia de operações foi iniciado 
   if (IsNovoDia())
   {
      ultimo_sinal = NULO;
   }
   
   //Obtem a situação do início do dia   
   if (ultimo_sinal == NULO)
      ultimo_sinal = CheckSinal();

   //Verifica se há um novo candle fechado
   bool novo_candle = IsNovoCandle();
   
   if(novo_candle)
   {
   
      //Verifica se o limite de gain ou loss foi atingido e encerra o processamento
      if (CheckLimites()) 
         return;
   
      //Verifica se houve um sinal de compra ou venda
      ENUM_SINAL sinal = CheckSinal();
      
      //Verifica se deve alterar a posição aberta
      CheckPosicaoAberta(sinal);
      
      //Verifica se deve fechar alguma ordem aberta
      CheckOrdemAberta(sinal);
      
      //Verifica se deve fazer uma realização parcial
      CheckRealizacaoParcial();
      
      //Verifica se deve setar o stop loss para o preço de entrada
      CheckBreakEven();
       
      //Verifica se deve abrir alguma posição de compra ou venda 
      CheckNovaEntrada(sinal);
       
      //Verifica se o horário limite de operações foi alcançado
      CheckHorarioFechamento();
      
   }
}

//Se houver posição aberta e um sinal na posição contrária for lançado o stop loss da posição aberta é alterado
void CheckPosicaoAberta(ENUM_SINAL sinal)
 {
   if (IsPosicionado())
    {
      if ((IsComprado() && sinal == VENDA) || (IsVendido() && sinal == COMPRA))
         AlterarStopLoss(sinal);
    }
 }

//Se houver ordem aberta e um sinal na posição contrária for lançado a ordem é fechada imediatamente
void CheckOrdemAberta(ENUM_SINAL sinal)
 {
   if (IsOrdemLancada())
    {
      if ((IsOrdemCompra() && sinal == VENDA) || (IsOrdemVenda() && sinal == COMPRA))
         Fechar();  
    }
 }
 
//Se estiver no horário permitido para novas entradas e não houver posição aberta
//É lançada uma nova ordem de entrada na superação do candle de sinal
void CheckNovaEntrada(ENUM_SINAL sinal)
 {
   if (IsHorarioPermitido() && !IsPosicionado())
    {
      if (ultimo_sinal == VENDA && sinal == COMPRA) 
      {
         bool op = Comprar();
         
         if (op)
            ultimo_sinal = COMPRA;
            
      }
      else if (ultimo_sinal == COMPRA && sinal == VENDA)
      {
         bool op = Vender();
         
         if (op)
            ultimo_sinal = VENDA;
      }
    }
 }

//Se o horário limite para operações abertas foi alcançado, todas as ordens e operações abertas são fechadas imediatamente
void CheckHorarioFechamento()
 {
   if(IsHorarioFechamento())
   {
      if(IsPosicionado() || !IsOrdemLancada()) {
         Print("Horário limite atingido. Encerrando ordens e posições abertas");
         Fechar();
      }
   }
 }
 
//Se o limite diário de gain ou loss for atingido encerra ordens ou posições em aberto
bool CheckLimites()
 {

   if (LimiteGain > 0 && GetSaldoFinanceiro() >= LimiteGain)
   {
      Fechar();
      Print("Limite de Gain diário batido.");
      return true;
   }
   
   if (LimiteLoss > 0 && GetSaldoFinanceiro() <= (LimiteLoss*-1)) {
      Fechar();
      Print("Limite de Loss diário batido.");
      return true;
   }
   
   return false;
 }
 
//Se o saldo da operação atingir o valor definido para RP, realizamos parte da operação
void CheckRealizacaoParcial()
 {
   if (!IsPosicionado())
      return;
      
   double saldo = GetSaldoPosicaoEmPontos();
   int volume_atual = PositionGetDouble(POSITION_VOLUME);
   
   if (saldo >= RP && volume_atual == Volume)
   {
      
      ENUM_ORDER_TYPE tipo = ORDER_TYPE_BUY;
      double preco = simbolo.Bid();
      
      if (IsComprado())
      {
         tipo = ORDER_TYPE_SELL;
         preco = simbolo.Ask();
      }
      
      OrdemAMercado(tipo, preco, VolumeRP);
   }
   
 }
 
//Verifica se há um novo candle fechado
bool IsNovoCandle()
 {
   if(bars != Bars(_Symbol, _Period))
    {
       bars = Bars(_Symbol, _Period);
       return true;
    }
    
   return false;
}

//Verifica se o horário atual está dentro do intervalo de tempo permitido
bool IsHorarioPermitido()
 {
   MqlDateTime hora_atual;
   TimeToStruct(TimeCurrent(), hora_atual); 
      
   if (hora_atual.hour >= hora_inicial.hour && hora_atual.hour <= hora_final.hour)
   {
      if ((hora_inicial.hour == hora_final.hour) 
            && (hora_atual.min >= hora_inicial.min) && (hora_atual.min <= hora_final.min))
         return true;
   
      if (hora_atual.hour == hora_inicial.hour)
      {
         if (hora_atual.min >= hora_inicial.min)
            return true;
         else
            return false;
      }
      
      if (hora_atual.hour == hora_final.hour)
      {
         if (hora_atual.min <= hora_final.min)
            return true;
         else
            return false;
      }
      
      return true;
   }
   
   return false;
 }

//Verifica se o horário limite para operações foi alcançado
bool IsHorarioFechamento()
 {
   MqlDateTime hora_atual;
   TimeToStruct(TimeCurrent(), hora_atual); 
   
   if (hora_atual.hour > hora_fechamento.hour)
      return true;
   
   if ((hora_atual.hour == hora_fechamento.hour) && (hora_atual.min >= hora_fechamento.min))
      return true;

   return false;
 }
 
//Verifica se um novo dia de operações foi iniciado
bool IsNovoDia()
 {
   static datetime OldDay = 0;
   
   MqlRates mrate[];    
   ArraySetAsSeries(mrate,true);      
   CopyRates(_Symbol,TimeFrame,0,2,mrate);
   
   datetime lastbar_time = mrate[0].time;
   
   MqlDateTime time;
   TimeToStruct(lastbar_time, time);
   
   if(OldDay < time.day_of_year)
   { 
      OldDay = time.day_of_year;
      return true;
   }
   
   return false;
 }

//Lança uma ordem pendente de compra na máxima do candle de sinal
//O stop loss é setado na mínima do candle de sinal
//O take profit é setado de acordo com o input informado pelo usuário
bool Comprar()
{

   double preco_entrada =  simbolo.NormalizePrice(GetPrecoEntrada(COMPRA));
   double stop_loss = simbolo.NormalizePrice(GetStopLoss(COMPRA));
   double take_profit = simbolo.NormalizePrice(preco_entrada + TP);

   ZerarRequest();
   
   request.action       = TRADE_ACTION_PENDING;
   request.magic        = magic_number;
   request.symbol       = _Symbol;
   request.volume       = Volume;
   request.price        = preco_entrada; 
   request.sl           = stop_loss;
   request.tp           = take_profit;
   request.type         = ORDER_TYPE_BUY_STOP;
   request.type_filling = ORDER_FILLING_RETURN; 
   request.type_time    = ORDER_TIME_DAY;
   request.comment      = "Compra";
   
   return EnviarRequisicao();
   
}

//Lança uma ordem pendente de venda na mínima do candle de sinal
//O stop loss é setado na máxima do candle de sinal
//O take profit é setado de acordo com o input informado pelo usuário
bool Vender()
{

   double preco_entrada = simbolo.NormalizePrice(GetPrecoEntrada(VENDA));
   double stop_loss = simbolo.NormalizePrice(GetStopLoss(VENDA));
   double take_profit = simbolo.NormalizePrice(preco_entrada - TP); 
   
   ZerarRequest();
   
   request.action       = TRADE_ACTION_PENDING;
   request.magic        = magic_number;
   request.symbol       = _Symbol;
   request.volume       = Volume;
   request.price        = preco_entrada; 
   request.sl           = stop_loss;
   request.tp           = take_profit;
   request.type         = ORDER_TYPE_SELL_STOP;
   request.type_filling = ORDER_FILLING_RETURN; 
   request.type_time    = ORDER_TIME_DAY;
   request.comment      = "Venda";
   
   return EnviarRequisicao();

} 

//Verifica se há ordens pendentes ou posições abertas e as fecha imediatamente
void Fechar()
{  
   FecharOrdens();
   
   FecharPosicao();
}

//Fecha ordens abertas
void FecharOrdens()
 {
   if(OrdersTotal() != 0)
   {
      for(int i=OrdersTotal()-1; i>=0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL)==_Symbol)
         {
            ZerarRequest();
            
            request.action       = TRADE_ACTION_REMOVE;
            request.order        = ticket;
            request.comment      = "Removendo ordem";
            
            EnviarRequisicao();
         }
      }
   }
 }
 
//Fecha posições abertas
void FecharPosicao()
 {
   if(!PositionSelect(_Symbol))
      return;
      
   ZerarRequest();
   
   double volume_operacao = PositionGetDouble(POSITION_VOLUME);
   
   request.action       = TRADE_ACTION_DEAL;
   request.magic        = magic_number;
   request.symbol       = _Symbol;
   request.volume       = volume_operacao;
   request.type_filling = ORDER_FILLING_RETURN; 
   request.comment      = "Fechando posição";
      
   long tipo = PositionGetInteger(POSITION_TYPE);
   
   if(tipo == POSITION_TYPE_BUY)
   {
      request.price = simbolo.Bid(); 
      request.type = ORDER_TYPE_SELL;
   }
   else
   {
      request.price = simbolo.Ask(); 
      request.type = ORDER_TYPE_BUY;
   }
   
   EnviarRequisicao();
 }
 
//Altera o stop loss de uma posição aberta para o novo ponto de saída
bool AlterarStopLoss(ENUM_SINAL sinal)
 {
   if(!PositionSelect(_Symbol))
      return false;
      
   double novo_alvo = simbolo.NormalizePrice(GetPrecoEntrada(sinal));
   
   ZerarRequest();

   request.action    = TRADE_ACTION_SLTP;                          
   request.magic     = magic_number;                                           
   request.symbol    = _Symbol;                                  
   request.sl        = novo_alvo;                                     
   request.position  = PositionGetInteger(POSITION_TICKET);
   request.comment   = "Alterando Stop Loss";
   request.type_time = ORDER_TIME_DAY;
  
   return EnviarRequisicao();
   
 }
 
//Se o saldo da posição aberta atingir o valor setado o stop loss da posição é alterado para o ponto de entrada
bool CheckBreakEven()
{

   if(BE == 0)
      return false;
      
   if(!PositionSelect(_Symbol))
      return false;
      
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double stop_loss = PositionGetDouble(POSITION_SL);
   
   if (IsComprado() && stop_loss >= open)
      return false;
   else if (IsVendido() && stop_loss <= open)
      return false;
   
   double saldo_posicao = GetSaldoPosicaoEmPontos();
   
   if (saldo_posicao < BE) {
      return false;
   }
   
   ZerarRequest();

   request.action    = TRADE_ACTION_SLTP;
   request.magic     = magic_number;
   request.symbol    = _Symbol;
   request.sl        = open;                                     
   request.tp        = PositionGetDouble(POSITION_TP);       
   request.position  = PositionGetInteger(POSITION_TICKET);   
   request.comment   = "Break Even"; 
   request.type_time = ORDER_TIME_DAY;

   return EnviarRequisicao();
      
}

bool OrdemAMercado(ENUM_ORDER_TYPE tipo, double preco, int volume)
{

   preco =  simbolo.NormalizePrice(preco);

   ZerarRequest();
   
   request.action       = TRADE_ACTION_DEAL;
   request.magic        = magic_number;
   request.symbol       = _Symbol;
   request.volume       = volume;
   request.price        = preco; 
   request.type         = tipo;
   request.type_filling = ORDER_FILLING_RETURN; 
   request.type_time    = ORDER_TIME_DAY;
   request.comment      = "Realizaçao Parcial";
   
   return EnviarRequisicao();
   
}
 
//Limpa estrutura de requisição de roteamento
void ZerarRequest()
 {
   ZeroMemory(request);
   ZeroMemory(result);
   ZeroMemory(check_result);
 }
 
//Valida e envia requisição de roteamento
bool EnviarRequisicao()
 {
   ResetLastError();
   
   PrintFormat("Request - %s, VOLUME: %.0f, PRICE: %.2f, SL: %.2f, TP: %.2f", request.comment, request.volume, request.price, request.sl, request.tp);
   
   if(!OrderCheck(request, check_result))
   {
      PrintFormat("Erro em OrderCheck: %d - Código: %d", GetLastError(), check_result.retcode);
      return false;
   }
   
   if(!OrderSend(request, result))
   {
      PrintFormat("Erro em OrderSend: %d - Código: %d", GetLastError(), result.retcode);
      return false;
   }
   
   return true;
 }

//Verifica se há um novo sinal de compra ou venda
//Se a média virar pra cima lança um sinal de compra
//Se a média virar pra baixo lança um sinal de venda
ENUM_SINAL CheckSinal()
 {
   double media_buffer[];
   CopyBuffer(handle_media, 0, 0, 2, media_buffer);
   ArraySetAsSeries(media_buffer, true);
   
   if (media_buffer[0] > media_buffer[1])
      return COMPRA;
   
   if (media_buffer[0] < media_buffer[1])
      return VENDA;
   
   return NULO;
 }
 
//Obtem o preço de entrada para compra ou venda
//Se o sinal for de compra, obtem a máxima do candle
//Se o sinal for de venda, obtem a minima do candle
double GetPrecoEntrada(ENUM_SINAL sinal)
 {
   MqlRates rate[];
   ArraySetAsSeries(rate, true);
   CopyRates(_Symbol, TimeFrame, 0, 2, rate);
   
   if (sinal == COMPRA)
      return rate[1].high;
   
   if (sinal == VENDA)
      return rate[1].low;
   
   return -1;
 }
 
//Obtem o preço de stop loss para compra ou venda
//Se o sinal for de compra, obtem a minima do candle
//Se o sinal for de venda, obtem a maxima do candle
double GetStopLoss(ENUM_SINAL sinal)
 {
   MqlRates rate[];
   ArraySetAsSeries(rate, true);
   CopyRates(_Symbol, TimeFrame, 0, 2, rate);
   
   if (sinal == COMPRA)
      return rate[1].low;
   
   if (sinal == VENDA)
      return rate[1].high;
      
   return -1;
 }

//Verifica se há posição no ativo
bool IsPosicionado()
 {  
   return PositionSelect(_Symbol);
 }

//Verifica se há alguma ordem lançada no ativo
bool IsOrdemLancada()
 {  
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL)==_Symbol)
         return true;
   }
   return false;
 }

//Verifica se há posição compradora aberta
bool IsComprado()
 {
   if(!PositionSelect(_Symbol))
      return false;
   
   return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
 }

//Verifica se há posição vendida aberta
bool IsVendido() 
 {
   if(!PositionSelect(_Symbol))
      return false;
   
   return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;
 }

//Verifica se há ordem de compra aberta
bool IsOrdemCompra()
 {  
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      OrderGetTicket(i);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      return type == ORDER_TYPE_BUY_STOP;
   }
   return false;
 }

//Verifica se há ordem de venda aberta
bool IsOrdemVenda()
 {  
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      OrderGetTicket(i);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      return type == ORDER_TYPE_SELL_STOP;
   }
   return false;
 }
 
double GetSaldoFinanceiro()
 {

   datetime end = TimeCurrent();
   datetime start = end - (end % 86400); // Hora inicial do dia

   HistorySelect(start, end);
   int deals = HistoryDealsTotal();

   double deal_profit = 0;
   
   for(int i=0 ; i < deals; i++)
   {
      
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket > 0) 
      {
         string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   
         if (deal_symbol == _Symbol) 
            deal_profit = deal_profit + HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      }
   }
  
   return deal_profit;
 }
 
double GetSaldoPosicaoEmPontos()
 {
   if (!IsPosicionado())
      return 0;
          
   ENUM_POSITION_TYPE tipo = PositionGetInteger(POSITION_TYPE);
   ENUM_POSITION_PROPERTY_DOUBLE pc = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_PROPERTY_DOUBLE po = PositionGetDouble(POSITION_PRICE_OPEN);
  
   if (tipo == POSITION_TYPE_SELL) {
      return po - pc;  
   } else if (tipo == POSITION_TYPE_BUY) {
      return pc - po; 
   }  
 
   return 0;
 }
