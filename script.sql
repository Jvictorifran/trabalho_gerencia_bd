-- =============================================================================
-- UNIVERSIDADE FEDERAL DA GRANDE DOURADOS
-- Disciplina: Projeto de Banco de Dados
-- Acadêmicos: João Victor Candido Ifran e Joaquim Peres Neto
--
-- SISTEMA DE MONITORAMENTO AGRÍCOLA POR IMAGENS DE SATÉLITE
-- script.sql -- Projeto Físico do Banco de Dados (Nota 1)
--
-- SGBD: MySQL 8.0 (InnoDB)  |  Codificação: utf8mb4 / utf8mb4_0900_ai_ci
-- Modelo relacional de origem: projeto_logico.mwb (MySQL Workbench)
--
-- CONTEÚDO DESTE SCRIPT
--   1. Criação do banco de dados
--   2. Criação das tabelas (DDL), com chaves e restrições de integridade
--   3. Índices do projeto físico
--   4. Gatilhos (regras que a restrição CHECK não expressa)
--   5. Visões de apoio (atributos derivados NÃO são armazenados)
--   6. Carga de dados (INSERT)
--   7. Consultas de verificação de consistência e testes das restrições
--   8. Backup e restauração
--
-- COMO EXECUTAR
--   mysql -u root -p < script.sql
--   ou, no MySQL Workbench: File > Open SQL Script > executar (raio)
-- =============================================================================

SET NAMES utf8mb4;
SET SQL_MODE = 'STRICT_ALL_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';


-- =============================================================================
-- 1. CRIAÇÃO DO BANCO DE DADOS
-- =============================================================================
-- O DROP inicial deixa o script totalmente reexecutável, o que facilita os
-- testes e a demonstração do projeto.

DROP DATABASE IF EXISTS `monitoramento_agricola`;

CREATE DATABASE `monitoramento_agricola`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE `monitoramento_agricola`;


-- =============================================================================
-- 2. CRIAÇÃO DAS TABELAS (DDL)
-- =============================================================================
-- As tabelas são criadas na ordem das dependências (uma tabela só é criada
-- depois daquela que ela referencia), de modo que nenhuma chave estrangeira
-- precise ser adicionada posteriormente.
--
-- Decisões de tipo de dado relevantes:
--   * cpf .......... CHAR(11): identificador tratado como texto, para preservar
--                    zeros à esquerda (um CPF não é uma quantidade).
--   * senha_hash ... VARCHAR(255): armazena o hash, nunca a senha em claro.
--   * tamanho ...... DECIMAL(10,2): valor exato em hectares; DECIMAL evita o
--                    erro de arredondamento de FLOAT/DOUBLE.
--   * valores dos índices ... DECIMAL(6,4): NDVI/EVI/NDWI pertencem a [-1, 1] e
--                    exigem quatro casas decimais.
--   * localizacao .. TEXT com geometria em WKT.
--   * url_arquivo .. VARCHAR(500): o raster fica em armazenamento externo e o
--                    banco guarda apenas o caminho (ver documentação, seção de
--                    decisões do projeto físico).


-- -----------------------------------------------------------------------------
-- Tabela `usuario`
-- Usuários do sistema: produtores, técnicos e administradores (RF02).
-- -----------------------------------------------------------------------------
CREATE TABLE `usuario` (
  `id_usuario` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único do usuário (PK).',
  `nome` VARCHAR(120) NOT NULL
      COMMENT 'Nome completo do usuário.',
  `cpf` CHAR(11) NOT NULL
      COMMENT 'CPF somente dígitos; texto para preservar zeros à esquerda.',
  `email` VARCHAR(120) NOT NULL
      COMMENT 'E-mail de contato e login.',
  `senha_hash` VARCHAR(255) NOT NULL
      COMMENT 'Hash da senha de acesso (RNF01).',
  `tipo` ENUM('produtor','tecnico','administrador') NOT NULL
      COMMENT 'Perfil de acesso do usuário (RF09).',
  PRIMARY KEY (`id_usuario`),
  CONSTRAINT `uq_usuario_cpf` UNIQUE (`cpf`),
  CONSTRAINT `uq_usuario_email` UNIQUE (`email`),
  -- CPF deve conter exatamente 11 digitos numericos.
  CONSTRAINT `chk_usuario_cpf_digitos`
    CHECK (`cpf` REGEXP '^[0-9]{11}$'),
  -- Formato minimo de e-mail.
  CONSTRAINT `chk_usuario_email_formato`
    CHECK (`email` LIKE '%_@_%._%')
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Usuários do sistema: produtores, técnicos e administradores (RF02).';

-- -----------------------------------------------------------------------------
-- Tabela `area_cultivo`
-- Áreas de cultivo (talhões) sob responsabilidade de um produtor (RF04).
-- -----------------------------------------------------------------------------
CREATE TABLE `area_cultivo` (
  `id_area` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único da área (PK).',
  `nome` VARCHAR(100) NOT NULL
      COMMENT 'Nome ou apelido do talhão.',
  `localizacao` TEXT NOT NULL
      COMMENT 'Polígono/coordenadas da área em formato WKT.',
  `cultura` VARCHAR(60) NOT NULL
      COMMENT 'Cultura plantada.',
  `data_plantio` DATE NOT NULL
      COMMENT 'Data de plantio.',
  `tamanho` DECIMAL(10,2) NOT NULL
      COMMENT 'Tamanho da área em hectares.',
  `id_produtor` INT UNSIGNED NOT NULL
      COMMENT 'Produtor responsável pela área (FK).',
  PRIMARY KEY (`id_area`),
  CONSTRAINT `uq_area_nome_produtor` UNIQUE (`id_produtor`, `nome`),
  -- A area plantada deve ser maior que zero.
  CONSTRAINT `chk_area_tamanho_positivo`
    CHECK (`tamanho` > 0),
  CONSTRAINT `fk_area_cultivo_usuario`
    FOREIGN KEY (`id_produtor`) REFERENCES `usuario` (`id_usuario`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Áreas de cultivo (talhões) sob responsabilidade de um produtor (RF04).';

-- -----------------------------------------------------------------------------
-- Tabela `imagem_satelite`
-- Imagens de satélite adquiridas para cada área de cultivo (RF05).
-- -----------------------------------------------------------------------------
CREATE TABLE `imagem_satelite` (
  `id_imagem` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único da imagem (PK).',
  `satelite` VARCHAR(40) NOT NULL
      COMMENT 'Satélite de origem (Sentinel-2, Landsat-8...).',
  `data_aquisicao` DATE NOT NULL
      COMMENT 'Data de aquisição da imagem.',
  `resolucao` DECIMAL(6,2) NOT NULL
      COMMENT 'Resolução espacial em metros.',
  `perc_nuvens` DECIMAL(5,2) NOT NULL
      COMMENT 'Percentual de cobertura de nuvens (0-100).',
  `localizacao` TEXT NOT NULL
      COMMENT 'Área geográfica coberta pela imagem em formato WKT.',
  `url_arquivo` VARCHAR(500) NOT NULL
      COMMENT 'Caminho/URL do arquivo raster armazenado externamente.',
  `id_area` INT UNSIGNED NOT NULL
      COMMENT 'Área de cultivo associada à imagem (FK).',
  PRIMARY KEY (`id_imagem`),
  CONSTRAINT `uq_imagem_area_satelite_data` UNIQUE (`id_area`, `satelite`, `data_aquisicao`),
  -- Cobertura de nuvens expressa em percentual (0 a 100).
  CONSTRAINT `chk_imagem_perc_nuvens`
    CHECK (`perc_nuvens` >= 0 AND `perc_nuvens` <= 100),
  -- Resolucao espacial em metros deve ser positiva.
  CONSTRAINT `chk_imagem_resolucao_positiva`
    CHECK (`resolucao` > 0),
  CONSTRAINT `fk_imagem_satelite_area_cultivo`
    FOREIGN KEY (`id_area`) REFERENCES `area_cultivo` (`id_area`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Imagens de satélite adquiridas para cada área de cultivo (RF05).';

-- -----------------------------------------------------------------------------
-- Tabela `indice_vegetacao`
-- Índices de vegetação calculados a partir de cada imagem (RF06).
-- -----------------------------------------------------------------------------
CREATE TABLE `indice_vegetacao` (
  `id_indice` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único do índice (PK).',
  `tipo` ENUM('NDVI','EVI','NDWI','SAVI','GNDVI') NOT NULL
      COMMENT 'Tipo do índice de vegetação.',
  `valor_medio` DECIMAL(6,4) NOT NULL
      COMMENT 'Valor médio do índice na área.',
  `valor_min` DECIMAL(6,4) NOT NULL
      COMMENT 'Valor mínimo do índice.',
  `valor_max` DECIMAL(6,4) NOT NULL
      COMMENT 'Valor máximo do índice.',
  `data` DATE NOT NULL
      COMMENT 'Data de referência do cálculo.',
  `id_imagem` INT UNSIGNED NOT NULL
      COMMENT 'Imagem que originou o índice (FK).',
  PRIMARY KEY (`id_indice`),
  CONSTRAINT `uq_indice_imagem_tipo` UNIQUE (`id_imagem`, `tipo`),
  -- Indices normalizados variam no intervalo [-1, 1].
  CONSTRAINT `chk_indice_faixa_valores`
    CHECK (`valor_min` >= -1 AND `valor_max` <= 1),
  -- Coerencia entre minimo, medio e maximo.
  CONSTRAINT `chk_indice_ordem_valores`
    CHECK (`valor_min` <= `valor_medio` AND `valor_medio` <= `valor_max`),
  CONSTRAINT `fk_indice_vegetacao_imagem_satelite`
    FOREIGN KEY (`id_imagem`) REFERENCES `imagem_satelite` (`id_imagem`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Índices de vegetação calculados a partir de cada imagem (RF06).';

-- -----------------------------------------------------------------------------
-- Tabela `observacao_campo`
-- Observações registradas em campo por produtores e técnicos (RF07).
-- -----------------------------------------------------------------------------
CREATE TABLE `observacao_campo` (
  `id_observacao` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único da observação (PK).',
  `data` DATE NOT NULL
      COMMENT 'Data da observação.',
  `descricao` TEXT NOT NULL
      COMMENT 'Descrição do que foi observado em campo.',
  `id_area` INT UNSIGNED NOT NULL
      COMMENT 'Área de cultivo observada (FK).',
  `id_usuario` INT UNSIGNED NOT NULL
      COMMENT 'Usuário que registrou a observação (FK).',
  PRIMARY KEY (`id_observacao`),
  CONSTRAINT `fk_observacao_campo_area_cultivo`
    FOREIGN KEY (`id_area`) REFERENCES `area_cultivo` (`id_area`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_observacao_campo_usuario`
    FOREIGN KEY (`id_usuario`) REFERENCES `usuario` (`id_usuario`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Observações registradas em campo por produtores e técnicos (RF07).';

-- -----------------------------------------------------------------------------
-- Tabela `avaliacao`
-- Avaliações de imagens OU de índices feitas pelos usuários (RF08).
-- -----------------------------------------------------------------------------
CREATE TABLE `avaliacao` (
  `id_avaliacao` INT UNSIGNED NOT NULL AUTO_INCREMENT
      COMMENT 'Identificador único da avaliação (PK).',
  `nota` TINYINT UNSIGNED NOT NULL
      COMMENT 'Nota atribuída (1 a 5).',
  `comentario` TEXT NULL
      COMMENT 'Comentário do avaliador.',
  `data` DATE NOT NULL
      COMMENT 'Data da avaliação.',
  `id_usuario` INT UNSIGNED NOT NULL
      COMMENT 'Usuário que fez a avaliação (FK).',
  `id_imagem` INT UNSIGNED NULL
      COMMENT 'Imagem avaliada, quando aplicável (FK).',
  `id_indice` INT UNSIGNED NULL
      COMMENT 'Índice avaliado, quando aplicável (FK).',
  PRIMARY KEY (`id_avaliacao`),
  CONSTRAINT `uq_avaliacao_usuario_imagem` UNIQUE (`id_usuario`, `id_imagem`),
  CONSTRAINT `uq_avaliacao_usuario_indice` UNIQUE (`id_usuario`, `id_indice`),
  -- Nota de 1 a 5.
  CONSTRAINT `chk_avaliacao_nota`
    CHECK (`nota` BETWEEN 1 AND 5),
  -- RF08: a avaliacao refere-se a uma imagem OU a um indice, nunca a ambos.
  CONSTRAINT `chk_avaliacao_alvo_exclusivo`
    CHECK ((`id_imagem` IS NOT NULL AND `id_indice` IS NULL)
        OR (`id_imagem` IS NULL AND `id_indice` IS NOT NULL)),
  CONSTRAINT `fk_avaliacao_usuario`
    FOREIGN KEY (`id_usuario`) REFERENCES `usuario` (`id_usuario`)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_avaliacao_imagem_satelite`
    FOREIGN KEY (`id_imagem`) REFERENCES `imagem_satelite` (`id_imagem`)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_avaliacao_indice_vegetacao`
    FOREIGN KEY (`id_indice`) REFERENCES `indice_vegetacao` (`id_indice`)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = 'Avaliações de imagens OU de índices feitas pelos usuários (RF08).';


-- =============================================================================
-- 3. ÍNDICES DO PROJETO FÍSICO
-- =============================================================================
-- Chaves primárias e restrições UNIQUE já criaram os índices correspondentes na
-- seção anterior. Os índices abaixo são os de apoio à consulta, criados a partir
-- das operações que o sistema mais executa (RNF03 e RNF04).
--
-- Observação: o InnoDB cria automaticamente um índice para cada chave
-- estrangeira. Quando esse índice automático já servia à consulta, nenhum índice
-- extra foi criado, para não duplicar estrutura e não onerar as escritas.


-- usuario
-- Filtro por perfil, usado no controle de acesso e na gestão de usuários (RF09).
CREATE INDEX `idx_usuario_tipo`
  ON `usuario` (`tipo`);

-- area_cultivo
-- Índice da chave estrangeira: lista as áreas de um produtor (RF03). Criado
-- explicitamente para deixar a decisão registrada no script.
CREATE INDEX `idx_area_produtor`
  ON `area_cultivo` (`id_produtor`);
-- Relatórios e comparações por cultura plantada.
CREATE INDEX `idx_area_cultura`
  ON `area_cultivo` (`cultura`);

-- imagem_satelite
-- ÍNDICE MAIS IMPORTANTE DO PROJETO: atende à consulta central do sistema,
-- o histórico de imagens de uma área em ordem de data (RF06/RNF03). Sendo
-- composto e na ordem (área, data), serve tanto ao filtro quanto à ordenação,
-- e ainda substitui o índice isolado da chave estrangeira id_area.
CREATE INDEX `idx_imagem_area_data`
  ON `imagem_satelite` (`id_area`, `data_aquisicao`);
-- Comparação de resultados entre satélites de origem.
CREATE INDEX `idx_imagem_satelite`
  ON `imagem_satelite` (`satelite`);

-- indice_vegetacao
-- Série temporal de um tipo de índice (ex.: todo o NDVI de um período).
CREATE INDEX `idx_indice_tipo_data`
  ON `indice_vegetacao` (`tipo`, `data`);

-- observacao_campo
-- Observações de uma área em ordem cronológica (RF07).
CREATE INDEX `idx_observacao_area_data`
  ON `observacao_campo` (`id_area`, `data`);
-- Observações registradas por um usuário; também cobre a chave estrangeira.
CREATE INDEX `idx_observacao_usuario`
  ON `observacao_campo` (`id_usuario`);

-- avaliacao
-- Avaliações feitas por um usuário (RF08).
CREATE INDEX `idx_avaliacao_usuario`
  ON `avaliacao` (`id_usuario`);
-- Avaliações recebidas por uma imagem; cobre a chave estrangeira id_imagem.
CREATE INDEX `idx_avaliacao_imagem`
  ON `avaliacao` (`id_imagem`);
-- Avaliações recebidas por um índice; cobre a chave estrangeira id_indice.
CREATE INDEX `idx_avaliacao_indice`
  ON `avaliacao` (`id_indice`);

-- Índice de texto completo: busca por palavra no relato da observação (RNF05).
-- O FULLTEXT é indicado para TEXT, onde um índice B-tree comum não ajuda.
CREATE FULLTEXT INDEX `ftx_observacao_descricao`
  ON `observacao_campo` (`descricao`);


-- =============================================================================
-- 4. GATILHOS
-- =============================================================================
-- O RF03 exige que a área de cultivo esteja vinculada a um usuário do tipo
-- 'produtor'. Essa regra depende de consultar outra tabela e, no MySQL, a
-- restrição CHECK não aceita subconsulta; por isso ela é garantida por gatilho.

DELIMITER $$

CREATE TRIGGER `trg_area_cultivo_bi_produtor`
BEFORE INSERT ON `area_cultivo` FOR EACH ROW
BEGIN
  DECLARE v_tipo VARCHAR(20);
  SELECT `tipo` INTO v_tipo FROM `usuario` WHERE `id_usuario` = NEW.`id_produtor`;
  IF v_tipo <> 'produtor' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RF03: a area de cultivo deve pertencer a um usuario do tipo produtor.';
  END IF;
END$$

CREATE TRIGGER `trg_area_cultivo_bu_produtor`
BEFORE UPDATE ON `area_cultivo` FOR EACH ROW
BEGIN
  DECLARE v_tipo VARCHAR(20);
  IF NEW.`id_produtor` <> OLD.`id_produtor` THEN
    SELECT `tipo` INTO v_tipo FROM `usuario` WHERE `id_usuario` = NEW.`id_produtor`;
    IF v_tipo <> 'produtor' THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RF03: a area de cultivo deve pertencer a um usuario do tipo produtor.';
    END IF;
  END IF;
END$$

DELIMITER ;



-- =============================================================================
-- 5. VISÕES DE APOIO
-- =============================================================================
-- Nenhum atributo derivado é armazenado no banco. Quantidades, médias e demais
-- valores calculáveis são obtidos por consulta, o que elimina o risco de o valor
-- gravado divergir dos dados reais.

-- 5.1 Histórico de índices por área: consulta mais frequente do sistema.
CREATE OR REPLACE VIEW `vw_historico_indice_area` AS
SELECT  a.`id_area`,
        a.`nome`            AS `area`,
        a.`cultura`,
        u.`nome`            AS `produtor`,
        i.`satelite`,
        i.`data_aquisicao`,
        i.`perc_nuvens`,
        v.`tipo`            AS `indice`,
        v.`valor_medio`,
        v.`valor_min`,
        v.`valor_max`,
        v.`data`            AS `data_calculo`
FROM       `area_cultivo`     a
JOIN       `usuario`          u ON u.`id_usuario` = a.`id_produtor`
JOIN       `imagem_satelite`  i ON i.`id_area`    = a.`id_area`
JOIN       `indice_vegetacao` v ON v.`id_imagem`  = i.`id_imagem`;

-- 5.2 Resumo por área: todos os campos são DERIVADOS (calculados, não armazenados).
CREATE OR REPLACE VIEW `vw_resumo_area` AS
SELECT  a.`id_area`,
        a.`nome`      AS `area`,
        a.`cultura`,
        a.`tamanho`,
        u.`nome`      AS `produtor`,
        (SELECT COUNT(*) FROM `imagem_satelite`  i
           WHERE i.`id_area` = a.`id_area`)                        AS `qtd_imagens`,
        (SELECT COUNT(*) FROM `imagem_satelite`  i
           JOIN `indice_vegetacao` v ON v.`id_imagem` = i.`id_imagem`
           WHERE i.`id_area` = a.`id_area`)                        AS `qtd_indices`,
        (SELECT COUNT(*) FROM `observacao_campo` o
           WHERE o.`id_area` = a.`id_area`)                        AS `qtd_observacoes`,
        (SELECT ROUND(AVG(v.`valor_medio`), 4) FROM `imagem_satelite` i
           JOIN `indice_vegetacao` v ON v.`id_imagem` = i.`id_imagem`
           WHERE i.`id_area` = a.`id_area` AND v.`tipo` = 'NDVI')  AS `ndvi_medio`,
        (SELECT MAX(i.`data_aquisicao`) FROM `imagem_satelite` i
           WHERE i.`id_area` = a.`id_area`)                        AS `ultima_imagem`
FROM `area_cultivo` a
JOIN `usuario`      u ON u.`id_usuario` = a.`id_produtor`;

-- 5.3 Avaliações unificadas: resolve o alvo exclusivo do RF08 na leitura.
CREATE OR REPLACE VIEW `vw_avaliacao_detalhada` AS
SELECT  av.`id_avaliacao`,
        av.`data`,
        av.`nota`,
        av.`comentario`,
        u.`nome`  AS `avaliador`,
        u.`tipo`  AS `perfil_avaliador`,
        CASE WHEN av.`id_imagem` IS NOT NULL THEN 'imagem' ELSE 'indice' END AS `alvo`,
        COALESCE(CONCAT(i.`satelite`, ' ', i.`data_aquisicao`),
                 CONCAT(v.`tipo`, ' ', v.`data`))                            AS `descricao_alvo`
FROM      `avaliacao`        av
JOIN      `usuario`          u ON u.`id_usuario` = av.`id_usuario`
LEFT JOIN `imagem_satelite`  i ON i.`id_imagem`  = av.`id_imagem`
LEFT JOIN `indice_vegetacao` v ON v.`id_indice`  = av.`id_indice`;



-- =============================================================================
-- 6. CARGA DE DADOS
-- =============================================================================
-- Os dados são inseridos na ordem das dependências. As chaves primárias são
-- AUTO_INCREMENT, portanto as chaves estrangeiras usam os identificadores
-- gerados sequencialmente a partir de 1.


-- -----------------------------------------------------------------------------
-- usuario -- 12 usuários: 6 produtores, 4 técnicos e 2 administradores (RF02).
-- -----------------------------------------------------------------------------
INSERT INTO `usuario`
  (`nome`, `cpf`, `email`, `senha_hash`, `tipo`)
VALUES
  ('Antônio Carlos Ferreira', '01987654321', 'antonio.ferreira@fazendasantamaria.com.br', '$2y$10$UO8Rzy4TnyOKQtY2datbkKQX4RRltbbFpyhn2P6vKtqLAJsEBGptB', 'produtor'),
  ('Maria Aparecida Souza', '02876543219', 'maria.souza@agrosouza.com.br', '$2y$10$2B66APVHIe7hOMx6//VsnjOmI4emLRa/xkkhflxhsgScqRyadWcYv', 'produtor'),
  ('José Roberto Nakamura', '03765432198', 'jose.nakamura@fazendaitamarati.com.br', '$2y$10$hq2HP8Grb3KqSjdfI56ZKRrUX3zO1wQinqCtqdAlG548xW84Cy.DL', 'produtor'),
  ('Luciana Prado Rodrigues', '04654321987', 'luciana.prado@agroprado.com.br', '$2y$10$lF90jNNFAQEjCwyamuUUe54P0fXrFgZRpr.806owd7sr6Amp5x.pb', 'produtor'),
  ('Sebastião Alves de Lima', '05543219876', 'sebastiao.lima@sitiobelavista.com.br', '$2y$10$8Mr4G1PA8jW.LRu7AumHXt39YJRuxKKT5beKExDbbrAfWgkz46M0L', 'produtor'),
  ('Helena Kruger Bauer', '06432198765', 'helena.bauer@fazendarecanto.com.br', '$2y$10$A0KyguTRmwgbz/uZVBt87YojGQAGoRXayVZkANnEWepbbS7atoUSr', 'produtor'),
  ('Rafael Mendes Tavares', '17321987654', 'rafael.tavares@ufgd.edu.br', '$2y$10$8zftqxdjq7h9bMw28ApCnO0HXkm.Plgv58uC2HRXAL0L5C2C3lH5u', 'tecnico'),
  ('Camila Ortiz Figueiredo', '18219876543', 'camila.figueiredo@ufgd.edu.br', '$2y$10$hrZSGvkqCSGFJd0Rnhh/fILrjvrKhYkrcXF4LiaBpr5EZuL9r7K.7', 'tecnico'),
  ('Bruno Yamaguchi Costa', '19198765432', 'bruno.costa@embrapa.br', '$2y$10$OVeaRl7QT27xuRoJN6eIQoUJC3ixQS/1oUzbIOgVOLnUJe51QUUVf', 'tecnico'),
  ('Patrícia Lemos Andrade', '20187654321', 'patricia.andrade@embrapa.br', '$2y$10$5JNqFlG8cLcMs38P8QY/H3JKXRiqyFG7DRDjOkVeYOo.ONydeEUNg', 'tecnico'),
  ('João Victor Candido Ifran', '31876543210', 'joao.ifran@ufgd.edu.br', '$2y$10$8Ungz6p7Q8jVF0r.3d9R5EiOAvM58VeeGxHZknrbRKUpd3jnIMCuS', 'administrador'),
  ('Joaquim Peres Neto', '32765432109', 'joaquim.neto@ufgd.edu.br', '$2y$10$aEvZs1gPH3100xjrvxHwXiQ4ui.UndOyA0pkhxDJRTGruPT7VVvAP', 'administrador');

-- -----------------------------------------------------------------------------
-- area_cultivo -- 10 áreas de cultivo na região de Dourados/MS (RF04).
-- -----------------------------------------------------------------------------
INSERT INTO `area_cultivo`
  (`nome`, `localizacao`, `cultura`, `data_plantio`, `tamanho`, `id_produtor`)
VALUES
  ('Talhão A1 - Sede', 'POLYGON((-54.831000 -22.182000, -54.805000 -22.182000, -54.805000 -22.204000, -54.831000 -22.204000, -54.831000 -22.182000))', 'Soja', '2025-10-18', 148.5, 1),
  ('Talhão A2 - Baixada', 'POLYGON((-54.822500 -22.190500, -54.796500 -22.190500, -54.796500 -22.212500, -54.822500 -22.212500, -54.822500 -22.190500))', 'Milho safrinha', '2026-02-12', 96.3, 1),
  ('Talhão B1 - Córrego', 'POLYGON((-54.769000 -22.245000, -54.743000 -22.245000, -54.743000 -22.267000, -54.769000 -22.267000, -54.769000 -22.245000))', 'Soja', '2025-10-25', 212.75, 2),
  ('Talhão B2 - Estrada', 'POLYGON((-54.760500 -22.253000, -54.734500 -22.253000, -54.734500 -22.275000, -54.760500 -22.275000, -54.760500 -22.253000))', 'Milho', '2026-02-20', 134.0, 2),
  ('Gleba Itamarati Norte', 'POLYGON((-54.912000 -22.064000, -54.886000 -22.064000, -54.886000 -22.086000, -54.912000 -22.086000, -54.912000 -22.064000))', 'Cana-de-açúcar', '2025-09-30', 385.6, 3),
  ('Gleba Itamarati Sul', 'POLYGON((-54.904000 -22.080500, -54.878000 -22.080500, -54.878000 -22.102500, -54.904000 -22.102500, -54.904000 -22.080500))', 'Soja', '2025-11-05', 274.2, 3),
  ('Talhão do Cerrado', 'POLYGON((-54.698000 -22.311000, -54.672000 -22.311000, -54.672000 -22.333000, -54.698000 -22.333000, -54.698000 -22.311000))', 'Algodão', '2025-12-08', 168.9, 4),
  ('Talhão da Mata', 'POLYGON((-54.687500 -22.320500, -54.661500 -22.320500, -54.661500 -22.342500, -54.687500 -22.342500, -54.687500 -22.320500))', 'Soja', '2025-10-30', 121.45, 4),
  ('Quadra 1 - Bela Vista', 'POLYGON((-54.561000 -22.402000, -54.535000 -22.402000, -54.535000 -22.424000, -54.561000 -22.424000, -54.561000 -22.402000))', 'Trigo', '2026-04-15', 64.8, 5),
  ('Recanto - Pivô Central', 'POLYGON((-55.024000 -21.993000, -54.998000 -21.993000, -54.998000 -22.015000, -55.024000 -22.015000, -55.024000 -21.993000))', 'Milho', '2026-02-28', 102.15, 6);

-- -----------------------------------------------------------------------------
-- imagem_satelite -- 45 imagens de satélite; apenas a URL é persistida (RF05).
-- -----------------------------------------------------------------------------
INSERT INTO `imagem_satelite`
  (`satelite`, `data_aquisicao`, `resolucao`, `perc_nuvens`, `localizacao`, `url_arquivo`, `id_area`)
VALUES
  ('Landsat-9', '2025-11-01', 30.0, 1.27, 'POLYGON((-54.835000 -22.178000, -54.801000 -22.178000, -54.801000 -22.208000, -54.835000 -22.208000, -54.835000 -22.178000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L9_20251101_area01.tif', 1),
  ('Landsat-9', '2025-11-25', 30.0, 13.28, 'POLYGON((-54.835000 -22.178000, -54.801000 -22.178000, -54.801000 -22.208000, -54.835000 -22.208000, -54.835000 -22.178000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L9_20251125_area01.tif', 1),
  ('Landsat-8', '2025-12-14', 30.0, 3.59, 'POLYGON((-54.835000 -22.178000, -54.801000 -22.178000, -54.801000 -22.208000, -54.835000 -22.208000, -54.835000 -22.178000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L8_20251214_area01.tif', 1),
  ('Landsat-9', '2026-01-07', 30.0, 8.31, 'POLYGON((-54.835000 -22.178000, -54.801000 -22.178000, -54.801000 -22.208000, -54.835000 -22.208000, -54.835000 -22.178000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260107_area01.tif', 1),
  ('Sentinel-2B', '2026-02-28', 10.0, 1.28, 'POLYGON((-54.826500 -22.186500, -54.792500 -22.186500, -54.792500 -22.216500, -54.826500 -22.216500, -54.826500 -22.186500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260228_area02.tif', 2),
  ('Sentinel-2B', '2026-03-19', 10.0, 1.48, 'POLYGON((-54.826500 -22.186500, -54.792500 -22.186500, -54.792500 -22.216500, -54.826500 -22.216500, -54.826500 -22.186500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260319_area02.tif', 2),
  ('Landsat-9', '2026-04-05', 30.0, 18.32, 'POLYGON((-54.826500 -22.186500, -54.792500 -22.186500, -54.792500 -22.216500, -54.826500 -22.216500, -54.826500 -22.186500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260405_area02.tif', 2),
  ('Sentinel-2A', '2026-05-01', 10.0, 18.24, 'POLYGON((-54.826500 -22.186500, -54.792500 -22.186500, -54.792500 -22.216500, -54.826500 -22.216500, -54.826500 -22.186500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260501_area02.tif', 2),
  ('Landsat-8', '2025-11-06', 30.0, 3.79, 'POLYGON((-54.773000 -22.241000, -54.739000 -22.241000, -54.739000 -22.271000, -54.773000 -22.271000, -54.773000 -22.241000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L8_20251106_area03.tif', 3),
  ('Sentinel-2B', '2025-12-03', 10.0, 2.93, 'POLYGON((-54.773000 -22.241000, -54.739000 -22.241000, -54.739000 -22.271000, -54.773000 -22.271000, -54.773000 -22.241000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/S2_20251203_area03.tif', 3),
  ('Sentinel-2B', '2025-12-21', 10.0, 0.56, 'POLYGON((-54.773000 -22.241000, -54.739000 -22.241000, -54.739000 -22.271000, -54.773000 -22.271000, -54.773000 -22.241000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/S2_20251221_area03.tif', 3),
  ('Sentinel-2A', '2026-01-12', 10.0, 24.79, 'POLYGON((-54.773000 -22.241000, -54.739000 -22.241000, -54.739000 -22.271000, -54.773000 -22.271000, -54.773000 -22.241000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260112_area03.tif', 3),
  ('Sentinel-2A', '2026-03-11', 10.0, 8.37, 'POLYGON((-54.764500 -22.249000, -54.730500 -22.249000, -54.730500 -22.279000, -54.764500 -22.279000, -54.764500 -22.249000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260311_area04.tif', 4),
  ('Landsat-9', '2026-04-04', 30.0, 1.22, 'POLYGON((-54.764500 -22.249000, -54.730500 -22.249000, -54.730500 -22.279000, -54.764500 -22.279000, -54.764500 -22.249000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260404_area04.tif', 4),
  ('Sentinel-2B', '2026-04-26', 10.0, 25.33, 'POLYGON((-54.764500 -22.249000, -54.730500 -22.249000, -54.730500 -22.279000, -54.764500 -22.279000, -54.764500 -22.249000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260426_area04.tif', 4),
  ('Landsat-8', '2026-05-26', 30.0, 6.21, 'POLYGON((-54.764500 -22.249000, -54.730500 -22.249000, -54.730500 -22.279000, -54.764500 -22.279000, -54.764500 -22.249000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L8_20260526_area04.tif', 4),
  ('Landsat-8', '2026-06-20', 30.0, 3.75, 'POLYGON((-54.764500 -22.249000, -54.730500 -22.249000, -54.730500 -22.279000, -54.764500 -22.279000, -54.764500 -22.249000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L8_20260620_area04.tif', 4),
  ('Landsat-8', '2025-11-09', 30.0, 18.52, 'POLYGON((-54.916000 -22.060000, -54.882000 -22.060000, -54.882000 -22.090000, -54.916000 -22.090000, -54.916000 -22.060000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L8_20251109_area05.tif', 5),
  ('Landsat-9', '2026-01-04', 30.0, 25.49, 'POLYGON((-54.916000 -22.060000, -54.882000 -22.060000, -54.882000 -22.090000, -54.916000 -22.090000, -54.916000 -22.060000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260104_area05.tif', 5),
  ('Sentinel-2A', '2026-03-04', 10.0, 18.94, 'POLYGON((-54.916000 -22.060000, -54.882000 -22.060000, -54.882000 -22.090000, -54.916000 -22.090000, -54.916000 -22.060000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260304_area05.tif', 5),
  ('Landsat-9', '2026-05-06', 30.0, 12.98, 'POLYGON((-54.916000 -22.060000, -54.882000 -22.060000, -54.882000 -22.090000, -54.916000 -22.090000, -54.916000 -22.060000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260506_area05.tif', 5),
  ('Sentinel-2B', '2025-11-20', 10.0, 3.56, 'POLYGON((-54.908000 -22.076500, -54.874000 -22.076500, -54.874000 -22.106500, -54.908000 -22.106500, -54.908000 -22.076500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/S2_20251120_area06.tif', 6),
  ('Sentinel-2A', '2025-12-13', 10.0, 13.05, 'POLYGON((-54.908000 -22.076500, -54.874000 -22.076500, -54.874000 -22.106500, -54.908000 -22.106500, -54.908000 -22.076500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/S2_20251213_area06.tif', 6),
  ('Sentinel-2A', '2026-01-03', 10.0, 0.69, 'POLYGON((-54.908000 -22.076500, -54.874000 -22.076500, -54.874000 -22.106500, -54.908000 -22.106500, -54.908000 -22.076500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260103_area06.tif', 6),
  ('Sentinel-2A', '2026-01-26', 10.0, 18.84, 'POLYGON((-54.908000 -22.076500, -54.874000 -22.076500, -54.874000 -22.106500, -54.908000 -22.106500, -54.908000 -22.076500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260126_area06.tif', 6),
  ('Landsat-9', '2026-02-21', 30.0, 25.24, 'POLYGON((-54.908000 -22.076500, -54.874000 -22.076500, -54.874000 -22.106500, -54.908000 -22.106500, -54.908000 -22.076500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260221_area06.tif', 6),
  ('Landsat-8', '2025-12-29', 30.0, 5.98, 'POLYGON((-54.702000 -22.307000, -54.668000 -22.307000, -54.668000 -22.337000, -54.702000 -22.337000, -54.702000 -22.307000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L8_20251229_area07.tif', 7),
  ('Landsat-9', '2026-01-26', 30.0, 18.45, 'POLYGON((-54.702000 -22.307000, -54.668000 -22.307000, -54.668000 -22.337000, -54.702000 -22.337000, -54.702000 -22.307000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260126_area07.tif', 7),
  ('Landsat-8', '2026-03-01', 30.0, 0.88, 'POLYGON((-54.702000 -22.307000, -54.668000 -22.307000, -54.668000 -22.337000, -54.702000 -22.337000, -54.702000 -22.307000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L8_20260301_area07.tif', 7),
  ('Sentinel-2B', '2026-04-05', 10.0, 3.36, 'POLYGON((-54.702000 -22.307000, -54.668000 -22.307000, -54.668000 -22.337000, -54.702000 -22.337000, -54.702000 -22.307000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260405_area07.tif', 7),
  ('Landsat-9', '2025-11-13', 30.0, 2.95, 'POLYGON((-54.691500 -22.316500, -54.657500 -22.316500, -54.657500 -22.346500, -54.691500 -22.346500, -54.691500 -22.316500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L9_20251113_area08.tif', 8),
  ('Landsat-8', '2025-12-09', 30.0, 1.32, 'POLYGON((-54.691500 -22.316500, -54.657500 -22.316500, -54.657500 -22.346500, -54.691500 -22.346500, -54.691500 -22.316500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/L8_20251209_area08.tif', 8),
  ('Sentinel-2A', '2025-12-27', 10.0, 0.46, 'POLYGON((-54.691500 -22.316500, -54.657500 -22.316500, -54.657500 -22.346500, -54.691500 -22.346500, -54.691500 -22.316500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2025/S2_20251227_area08.tif', 8),
  ('Sentinel-2B', '2026-01-18', 10.0, 13.16, 'POLYGON((-54.691500 -22.316500, -54.657500 -22.316500, -54.657500 -22.346500, -54.691500 -22.346500, -54.691500 -22.316500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260118_area08.tif', 8),
  ('Landsat-9', '2026-02-11', 30.0, 1.47, 'POLYGON((-54.691500 -22.316500, -54.657500 -22.316500, -54.657500 -22.346500, -54.691500 -22.346500, -54.691500 -22.316500))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260211_area08.tif', 8),
  ('Sentinel-2B', '2026-04-30', 10.0, 6.5, 'POLYGON((-54.565000 -22.398000, -54.531000 -22.398000, -54.531000 -22.428000, -54.565000 -22.428000, -54.565000 -22.398000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260430_area09.tif', 9),
  ('Sentinel-2B', '2026-05-21', 10.0, 18.6, 'POLYGON((-54.565000 -22.398000, -54.531000 -22.398000, -54.531000 -22.428000, -54.565000 -22.428000, -54.565000 -22.398000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260521_area09.tif', 9),
  ('Sentinel-2A', '2026-06-04', 10.0, 25.35, 'POLYGON((-54.565000 -22.398000, -54.531000 -22.398000, -54.531000 -22.428000, -54.565000 -22.428000, -54.565000 -22.398000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260604_area09.tif', 9),
  ('Landsat-9', '2026-06-25', 30.0, 8.5, 'POLYGON((-54.565000 -22.398000, -54.531000 -22.398000, -54.531000 -22.428000, -54.565000 -22.428000, -54.565000 -22.398000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260625_area09.tif', 9),
  ('Sentinel-2A', '2026-07-18', 10.0, 18.48, 'POLYGON((-54.565000 -22.398000, -54.531000 -22.398000, -54.531000 -22.428000, -54.565000 -22.428000, -54.565000 -22.398000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260718_area09.tif', 9),
  ('Landsat-9', '2026-03-14', 30.0, 6.08, 'POLYGON((-55.028000 -21.989000, -54.994000 -21.989000, -54.994000 -22.019000, -55.028000 -22.019000, -55.028000 -21.989000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L9_20260314_area10.tif', 10),
  ('Sentinel-2A', '2026-04-11', 10.0, 1.93, 'POLYGON((-55.028000 -21.989000, -54.994000 -21.989000, -54.994000 -22.019000, -55.028000 -22.019000, -55.028000 -21.989000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260411_area10.tif', 10),
  ('Sentinel-2A', '2026-05-03', 10.0, 3.7, 'POLYGON((-55.028000 -21.989000, -54.994000 -21.989000, -54.994000 -22.019000, -55.028000 -22.019000, -55.028000 -21.989000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260503_area10.tif', 10),
  ('Sentinel-2B', '2026-06-01', 10.0, 8.4, 'POLYGON((-55.028000 -21.989000, -54.994000 -21.989000, -54.994000 -22.019000, -55.028000 -22.019000, -55.028000 -21.989000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/S2_20260601_area10.tif', 10),
  ('Landsat-8', '2026-06-25', 30.0, 13.57, 'POLYGON((-55.028000 -21.989000, -54.994000 -21.989000, -54.994000 -22.019000, -55.028000 -22.019000, -55.028000 -21.989000))', 'https://storage.monitoramento-agricola.ufgd.edu.br/rasters/2026/L8_20260625_area10.tif', 10);

-- -----------------------------------------------------------------------------
-- indice_vegetacao -- 120 índices de vegetação calculados sobre as imagens (RF06).
-- -----------------------------------------------------------------------------
INSERT INTO `indice_vegetacao`
  (`tipo`, `valor_medio`, `valor_min`, `valor_max`, `data`, `id_imagem`)
VALUES
  ('NDVI', 0.5612, 0.4082, 0.6249, '2025-11-02', 1),
  ('NDWI', 0.1762, 0.0227, 0.2949, '2025-11-02', 1),
  ('EVI', 0.3969, 0.2229, 0.4905, '2025-11-03', 1),
  ('NDVI', 0.7803, 0.7079, 0.8484, '2025-11-25', 2),
  ('NDWI', 0.3648, 0.2562, 0.4051, '2025-11-25', 2),
  ('EVI', 0.6607, 0.589, 0.7113, '2025-11-26', 2),
  ('NDVI', 0.8406, 0.7792, 0.8795, '2025-12-15', 3),
  ('NDWI', 0.355, 0.2876, 0.4143, '2025-12-14', 3),
  ('NDVI', 0.7169, 0.6373, 0.7579, '2026-01-09', 4),
  ('EVI', 0.5975, 0.478, 0.6502, '2026-01-09', 4),
  ('NDWI', 0.2575, 0.1387, 0.3396, '2026-01-09', 4),
  ('NDVI', 0.6198, 0.518, 0.6834, '2026-03-01', 5),
  ('EVI', 0.4741, 0.3533, 0.5524, '2026-03-01', 5),
  ('NDWI', 0.1773, 0.02, 0.246, '2026-03-01', 5),
  ('NDVI', 0.8152, 0.74, 0.8534, '2026-03-20', 6),
  ('NDWI', 0.3638, 0.2687, 0.4212, '2026-03-21', 6),
  ('NDVI', 0.8509, 0.7586, 0.8888, '2026-04-05', 7),
  ('EVI', 0.694, 0.6374, 0.7507, '2026-04-06', 7),
  ('NDVI', 0.6887, 0.5717, 0.778, '2026-05-03', 8),
  ('EVI', 0.551, 0.4591, 0.6269, '2026-05-02', 8),
  ('NDVI', 0.4736, 0.2854, 0.5546, '2025-11-07', 9),
  ('NDWI', 0.1395, -0.0412, 0.2269, '2025-11-07', 9),
  ('EVI', 0.4075, 0.2609, 0.4793, '2025-11-07', 9),
  ('NDVI', 0.8013, 0.7115, 0.8391, '2025-12-03', 10),
  ('EVI', 0.6306, 0.568, 0.6785, '2025-12-04', 10),
  ('NDWI', 0.3717, 0.2943, 0.4194, '2025-12-05', 10),
  ('NDVI', 0.8721, 0.7883, 0.9208, '2025-12-22', 11),
  ('NDWI', 0.3859, 0.3094, 0.4301, '2025-12-21', 11),
  ('NDVI', 0.7538, 0.6756, 0.8298, '2026-01-13', 12),
  ('NDWI', 0.3027, 0.2229, 0.3856, '2026-01-14', 12),
  ('EVI', 0.5671, 0.4853, 0.6421, '2026-01-13', 12),
  ('NDVI', 0.5602, 0.424, 0.6609, '2026-03-12', 13),
  ('EVI', 0.4646, 0.3162, 0.5633, '2026-03-11', 13),
  ('NDWI', 0.2099, 0.1085, 0.3019, '2026-03-12', 13),
  ('NDVI', 0.8108, 0.7475, 0.8558, '2026-04-06', 14),
  ('EVI', 0.6396, 0.5516, 0.7074, '2026-04-05', 14),
  ('NDWI', 0.3461, 0.2637, 0.4005, '2026-04-05', 14),
  ('NDVI', 0.8157, 0.7203, 0.8524, '2026-04-27', 15),
  ('EVI', 0.6571, 0.5996, 0.6962, '2026-04-27', 15),
  ('NDWI', 0.389, 0.2955, 0.4399, '2026-04-28', 15),
  ('NDVI', 0.6683, 0.568, 0.7266, '2026-05-28', 16),
  ('NDWI', 0.253, 0.1483, 0.3253, '2026-05-27', 16),
  ('NDVI', 0.4404, 0.2861, 0.5626, '2026-06-20', 17),
  ('EVI', 0.3428, 0.2111, 0.408, '2026-06-21', 17),
  ('NDWI', 0.0778, -0.0613, 0.2039, '2026-06-22', 17),
  ('NDVI', 0.532, 0.3837, 0.6066, '2025-11-10', 18),
  ('NDWI', 0.1759, 0.0523, 0.2768, '2025-11-09', 18),
  ('EVI', 0.4252, 0.2645, 0.4775, '2025-11-11', 18),
  ('NDVI', 0.7845, 0.7104, 0.83, '2026-01-05', 19),
  ('NDWI', 0.3228, 0.2112, 0.3815, '2026-01-06', 19),
  ('EVI', 0.6678, 0.5781, 0.7173, '2026-01-04', 19),
  ('NDVI', 0.8615, 0.7946, 0.9202, '2026-03-04', 20),
  ('NDWI', 0.3659, 0.2952, 0.4133, '2026-03-05', 20),
  ('EVI', 0.7064, 0.6296, 0.747, '2026-03-04', 20),
  ('NDVI', 0.7059, 0.5951, 0.7908, '2026-05-08', 21),
  ('EVI', 0.5455, 0.4165, 0.621, '2026-05-07', 21),
  ('NDWI', 0.2489, 0.1271, 0.296, '2026-05-08', 21),
  ('NDVI', 0.5472, 0.382, 0.6502, '2025-11-21', 22),
  ('EVI', 0.448, 0.3305, 0.5102, '2025-11-22', 22),
  ('NDVI', 0.8086, 0.7417, 0.8771, '2025-12-13', 23),
  ('EVI', 0.6594, 0.584, 0.702, '2025-12-13', 23),
  ('NDWI', 0.3584, 0.2603, 0.4264, '2025-12-15', 23),
  ('NDVI', 0.8165, 0.7254, 0.8516, '2026-01-03', 24),
  ('EVI', 0.7084, 0.6254, 0.7604, '2026-01-03', 24),
  ('NDWI', 0.3883, 0.3021, 0.4365, '2026-01-03', 24),
  ('NDVI', 0.7208, 0.5961, 0.7728, '2026-01-27', 25),
  ('EVI', 0.5969, 0.5012, 0.6577, '2026-01-27', 25),
  ('NDVI', 0.4219, 0.2367, 0.5044, '2026-02-22', 26),
  ('EVI', 0.3463, 0.1823, 0.4104, '2026-02-23', 26),
  ('NDWI', 0.0765, -0.1125, 0.2136, '2026-02-23', 26),
  ('NDVI', 0.527, 0.3824, 0.6079, '2025-12-30', 27),
  ('NDWI', 0.1851, 0.0528, 0.2788, '2025-12-31', 27),
  ('NDVI', 0.7637, 0.6801, 0.7998, '2026-01-27', 28),
  ('NDWI', 0.3214, 0.2488, 0.3768, '2026-01-27', 28),
  ('EVI', 0.6492, 0.5357, 0.6959, '2026-01-27', 28),
  ('NDVI', 0.8713, 0.7952, 0.9344, '2026-03-01', 29),
  ('NDWI', 0.3881, 0.3, 0.4275, '2026-03-02', 29),
  ('EVI', 0.6679, 0.5973, 0.6974, '2026-03-02', 29),
  ('NDVI', 0.7159, 0.5908, 0.8031, '2026-04-06', 30),
  ('NDWI', 0.2815, 0.1717, 0.3395, '2026-04-06', 30),
  ('EVI', 0.5778, 0.4446, 0.6312, '2026-04-07', 30),
  ('NDVI', 0.5392, 0.4105, 0.6363, '2025-11-14', 31),
  ('EVI', 0.4034, 0.2393, 0.4752, '2025-11-14', 31),
  ('NDWI', 0.1354, -0.0353, 0.2509, '2025-11-13', 31),
  ('NDVI', 0.8118, 0.7498, 0.8519, '2025-12-10', 32),
  ('NDWI', 0.3226, 0.2481, 0.3815, '2025-12-11', 32),
  ('EVI', 0.6595, 0.5855, 0.7214, '2025-12-10', 32),
  ('NDVI', 0.8449, 0.7553, 0.8768, '2025-12-29', 33),
  ('EVI', 0.7111, 0.6428, 0.7476, '2025-12-27', 33),
  ('NDVI', 0.6993, 0.6117, 0.782, '2026-01-19', 34),
  ('NDWI', 0.2763, 0.1631, 0.3237, '2026-01-20', 34),
  ('EVI', 0.6083, 0.4857, 0.6834, '2026-01-19', 34),
  ('NDVI', 0.4451, 0.2979, 0.5459, '2026-02-12', 35),
  ('EVI', 0.353, 0.2317, 0.4511, '2026-02-11', 35),
  ('NDWI', 0.126, -0.0677, 0.2392, '2026-02-12', 35),
  ('NDVI', 0.5752, 0.4386, 0.6803, '2026-05-01', 36),
  ('EVI', 0.4356, 0.3075, 0.4847, '2026-05-02', 36),
  ('NDVI', 0.8069, 0.7154, 0.8535, '2026-05-23', 37),
  ('EVI', 0.6391, 0.5416, 0.6788, '2026-05-21', 37),
  ('NDVI', 0.8438, 0.7581, 0.8915, '2026-06-05', 38),
  ('EVI', 0.6991, 0.6354, 0.738, '2026-06-04', 38),
  ('NDWI', 0.3531, 0.2561, 0.4091, '2026-06-06', 38),
  ('NDVI', 0.7294, 0.598, 0.8027, '2026-06-25', 39),
  ('NDWI', 0.2775, 0.1876, 0.3294, '2026-06-26', 39),
  ('EVI', 0.5824, 0.4623, 0.6537, '2026-06-26', 39),
  ('NDVI', 0.4353, 0.2603, 0.5298, '2026-07-19', 40),
  ('EVI', 0.3096, 0.0979, 0.4361, '2026-07-19', 40),
  ('NDVI', 0.5355, 0.3744, 0.5925, '2026-03-14', 41),
  ('NDWI', 0.111, -0.0387, 0.2305, '2026-03-16', 41),
  ('NDVI', 0.8347, 0.7349, 0.8665, '2026-04-12', 42),
  ('NDWI', 0.3578, 0.2508, 0.3991, '2026-04-11', 42),
  ('NDVI', 0.8293, 0.7435, 0.8876, '2026-05-04', 43),
  ('NDWI', 0.3626, 0.3042, 0.4078, '2026-05-04', 43),
  ('EVI', 0.6763, 0.6008, 0.7126, '2026-05-04', 43),
  ('NDVI', 0.6726, 0.5561, 0.7165, '2026-06-03', 44),
  ('NDWI', 0.2565, 0.1229, 0.3269, '2026-06-03', 44),
  ('EVI', 0.567, 0.4718, 0.637, '2026-06-01', 44),
  ('NDVI', 0.4941, 0.3282, 0.5727, '2026-06-26', 45),
  ('NDWI', 0.115, -0.0381, 0.1819, '2026-06-26', 45),
  ('EVI', 0.3468, 0.162, 0.4252, '2026-06-26', 45);

-- -----------------------------------------------------------------------------
-- observacao_campo -- 20 observações de campo (RF07).
-- -----------------------------------------------------------------------------
INSERT INTO `observacao_campo`
  (`data`, `descricao`, `id_area`, `id_usuario`)
VALUES
  ('2025-11-22', 'Lavoura em bom estágio vegetativo, fechamento de entrelinhas uniforme e sem falhas aparentes.', 1, 1),
  ('2026-05-04', 'Identificada mancha de solo exposto no terço final do talhão; provável falha de plantio na semeadura.', 2, 10),
  ('2026-02-16', 'Presença de lagarta-do-cartucho em nível de controle; recomendada aplicação localizada.', 3, 8),
  ('2026-06-16', 'Sinais de estresse hídrico nas bordaduras, coincidindo com a queda de NDWI observada nas imagens.', 4, 10),
  ('2026-01-20', 'Aplicação de fungicida realizada conforme recomendação técnica; sem sintomas de ferrugem asiática.', 5, 9),
  ('2026-03-05', 'Solo com boa umidade após precipitação de 38 mm registrada na estação da propriedade.', 6, 7),
  ('2026-01-01', 'Plantas com altura irregular na faixa central; coleta de amostras de solo solicitada.', 7, 10),
  ('2025-12-25', 'Ocorrência pontual de plantas daninhas resistentes (capim-amargoso) próxima ao carreador.', 8, 8),
  ('2026-06-13', 'Talhão em início de enchimento de grãos, coloração uniforme e estande adequado.', 9, 5),
  ('2026-06-09', 'Verificada compactação de solo na área de tráfego de máquinas; NDVI reduzido na faixa.', 10, 7),
  ('2026-02-10', 'Desenvolvimento vegetativo acima da média histórica para o período; sem ocorrências fitossanitárias.', 1, 7),
  ('2026-05-01', 'Percevejo-marrom detectado em amostragem de pano; população abaixo do nível de dano econômico.', 2, 7),
  ('2025-11-20', 'Falha de germinação confirmada em campo na região indicada pelo índice NDVI mais baixo.', 3, 2),
  ('2026-05-04', 'Cultura em maturação fisiológica; colheita prevista para os próximos quinze dias.', 4, 8),
  ('2025-12-14', 'Área apresenta boa sanidade foliar; manejo de adubação de cobertura concluído.', 5, 9),
  ('2026-03-04', 'Encharcamento temporário na baixada após chuva intensa; NDWI elevado confirma a condição.', 6, 3),
  ('2026-03-27', 'Sintomas iniciais de mancha-alvo nas folhas baixeiras; monitoramento semanal mantido.', 7, 4),
  ('2025-12-14', 'Estande final avaliado em 292 mil plantas por hectare, dentro do esperado para a cultivar.', 8, 4),
  ('2026-07-21', 'Bordadura com crescimento reduzido por sombreamento da mata adjacente; situação esperada.', 9, 5),
  ('2026-06-23', 'Pivô ajustado após leitura dos índices; lâmina de irrigação corrigida para 22 mm.', 10, 9);

-- -----------------------------------------------------------------------------
-- avaliacao -- 30 avaliações, cada uma de uma imagem OU de um índice (RF08).
-- -----------------------------------------------------------------------------
INSERT INTO `avaliacao`
  (`nota`, `comentario`, `data`, `id_usuario`, `id_imagem`, `id_indice`)
VALUES
  (5, 'Valor médio compatível com o estágio fenológico da cultura.', '2025-11-08', 8, NULL, 2),
  (5, 'Índice ligeiramente otimista em relação à condição real da bordadura.', '2025-11-09', 9, NULL, 3),
  (3, 'Resultado consistente com a série histórica do talhão.', '2025-11-11', 9, NULL, 22),
  (5, 'Boa correlação com a leitura de umidade do solo registrada no campo.', '2025-11-16', 9, NULL, 48),
  (5, 'O valor mínimo reflete corretamente a falha identificada na vistoria.', '2025-11-22', 4, NULL, 83),
  (3, 'Imagem com baixa cobertura de nuvens e ótimo recorte do talhão.', '2025-12-02', 7, 2, NULL),
  (5, 'Cobertura de nuvens acima do ideal; recomendo usar a cena seguinte.', '2025-12-05', 3, 10, NULL),
  (5, 'Imagem útil, mas a data de aquisição ficou distante do estágio de interesse.', '2025-12-05', 4, 10, NULL),
  (5, 'Índice coerente com o que foi observado em campo na mesma semana.', '2025-12-20', 2, NULL, 86),
  (3, 'Excelente qualidade radiométrica, sem ruído perceptível.', '2025-12-20', 7, 23, NULL),
  (5, 'Excelente qualidade radiométrica, sem ruído perceptível.', '2025-12-23', 8, 11, NULL),
  (4, 'O valor mínimo reflete corretamente a falha identificada na vistoria.', '2025-12-27', 6, NULL, 28),
  (5, 'Imagem útil, mas a data de aquisição ficou distante do estágio de interesse.', '2026-01-06', 5, 24, NULL),
  (2, 'Boa nitidez; resolução suficiente para identificar as falhas de plantio.', '2026-01-06', 9, 19, NULL),
  (5, 'Excelente qualidade radiométrica, sem ruído perceptível.', '2026-01-12', 9, 24, NULL),
  (2, 'Recorte adequado, porém sombra de nuvem na borda norte prejudica parte da análise.', '2026-01-17', 10, 12, NULL),
  (4, 'Resultado consistente com a série histórica do talhão.', '2026-02-14', 5, NULL, 93),
  (4, 'O valor mínimo reflete corretamente a falha identificada na vistoria.', '2026-02-21', 8, NULL, 95),
  (5, 'Imagem com baixa cobertura de nuvens e ótimo recorte do talhão.', '2026-03-10', 1, 5, NULL),
  (5, 'Boa correlação com a leitura de umidade do solo registrada no campo.', '2026-03-18', 4, NULL, 108),
  (5, 'Imagem com baixa cobertura de nuvens e ótimo recorte do talhão.', '2026-04-14', 9, 42, NULL),
  (3, 'Boa correlação com a leitura de umidade do solo registrada no campo.', '2026-04-15', 5, NULL, 35),
  (2, 'Imagem útil, mas a data de aquisição ficou distante do estágio de interesse.', '2026-04-27', 1, 15, NULL),
  (4, 'Índice ligeiramente otimista em relação à condição real da bordadura.', '2026-05-06', 2, NULL, 97),
  (4, 'Recorte adequado, porém sombra de nuvem na borda norte prejudica parte da análise.', '2026-05-09', 3, 43, NULL),
  (4, 'Boa nitidez; resolução suficiente para identificar as falhas de plantio.', '2026-06-29', 6, 17, NULL),
  (5, 'Índice ligeiramente otimista em relação à condição real da bordadura.', '2026-07-02', 9, NULL, 105),
  (3, 'Imagem com baixa cobertura de nuvens e ótimo recorte do talhão.', '2026-07-05', 3, 45, NULL),
  (5, 'Índice ligeiramente otimista em relação à condição real da bordadura.', '2026-07-20', 6, NULL, 106),
  (3, 'Cobertura de nuvens acima do ideal; recomendo usar a cena seguinte.', '2026-07-28', 2, 40, NULL);


-- =============================================================================
-- 7. CONSULTAS DE VERIFICAÇÃO DE CONSISTÊNCIA
-- =============================================================================
-- As consultas 7.1 a 7.4 conferem o povoamento. As consultas 7.5 a 7.9 são
-- testes de integridade: todas devem retornar ZERO linha. Qualquer linha
-- devolvida indica inconsistência no modelo ou nos dados. A consulta 7.10
-- confere os índices criados e a seção 7.11 reúne os testes das restrições,
-- feitos com inserções propositalmente inválidas.

-- 7.1 Quantidade de registros por tabela.
SELECT 'usuario' AS tabela, COUNT(*) AS registros FROM `usuario`
UNION ALL SELECT 'area_cultivo',     COUNT(*) FROM `area_cultivo`
UNION ALL SELECT 'imagem_satelite',  COUNT(*) FROM `imagem_satelite`
UNION ALL SELECT 'indice_vegetacao', COUNT(*) FROM `indice_vegetacao`
UNION ALL SELECT 'observacao_campo', COUNT(*) FROM `observacao_campo`
UNION ALL SELECT 'avaliacao',        COUNT(*) FROM `avaliacao`;

-- 7.2 Cadeia completa produtor -> área -> imagem -> índice (junção de 4 tabelas).
SELECT  u.`nome` AS produtor, a.`nome` AS area, a.`cultura`,
        i.`satelite`, i.`data_aquisicao`, v.`tipo`, v.`valor_medio`
FROM       `usuario`          u
JOIN       `area_cultivo`     a ON a.`id_produtor` = u.`id_usuario`
JOIN       `imagem_satelite`  i ON i.`id_area`     = a.`id_area`
JOIN       `indice_vegetacao` v ON v.`id_imagem`   = i.`id_imagem`
ORDER BY u.`nome`, a.`nome`, i.`data_aquisicao`, v.`tipo`
LIMIT 20;

-- 7.3 Resumo por área, com os atributos derivados calculados na consulta.
SELECT * FROM `vw_resumo_area` ORDER BY `area`;

-- 7.4 Evolução do NDVI de uma área (histórico exigido pelo RF06).
SELECT `area`, `cultura`, `data_aquisicao`, `satelite`, `valor_medio` AS ndvi
FROM `vw_historico_indice_area`
WHERE `indice` = 'NDVI' AND `id_area` = 1
ORDER BY `data_aquisicao`;

-- 7.5 TESTE: toda área deve pertencer a um usuário do tipo 'produtor' (RF03).
SELECT a.`id_area`, a.`nome`, u.`tipo`
FROM `area_cultivo` a
JOIN `usuario` u ON u.`id_usuario` = a.`id_produtor`
WHERE u.`tipo` <> 'produtor';

-- 7.6 TESTE: toda avaliação refere-se a exatamente um alvo (RF08).
SELECT `id_avaliacao`, `id_imagem`, `id_indice`
FROM `avaliacao`
WHERE (`id_imagem` IS NULL AND `id_indice` IS NULL)
   OR (`id_imagem` IS NOT NULL AND `id_indice` IS NOT NULL);

-- 7.7 TESTE: coerência entre valor mínimo, médio e máximo dos índices.
SELECT `id_indice`, `tipo`, `valor_min`, `valor_medio`, `valor_max`
FROM `indice_vegetacao`
WHERE `valor_min` > `valor_medio` OR `valor_medio` > `valor_max`
   OR `valor_min` < -1 OR `valor_max` > 1;

-- 7.8 TESTE: nenhum índice órfão e nenhuma imagem sem área (integridade referencial).
SELECT v.`id_indice`
FROM `indice_vegetacao` v
LEFT JOIN `imagem_satelite` i ON i.`id_imagem` = v.`id_imagem`
WHERE i.`id_imagem` IS NULL;

-- 7.9 TESTE: a imagem que originou o índice deve pertencer à área observada.
-- Confere se a cadeia área -> imagem -> índice se mantém consistente.
SELECT v.`id_indice`, i.`id_imagem`, i.`id_area`
FROM `indice_vegetacao` v
JOIN `imagem_satelite` i ON i.`id_imagem` = v.`id_imagem`
LEFT JOIN `area_cultivo` a ON a.`id_area` = i.`id_area`
WHERE a.`id_area` IS NULL;

-- 7.10 Conferência dos índices efetivamente criados no banco.
SELECT `TABLE_NAME`, `INDEX_NAME`, `NON_UNIQUE`,
       GROUP_CONCAT(`COLUMN_NAME` ORDER BY `SEQ_IN_INDEX`) AS colunas
FROM `information_schema`.`STATISTICS`
WHERE `TABLE_SCHEMA` = 'monitoramento_agricola'
GROUP BY `TABLE_NAME`, `INDEX_NAME`, `NON_UNIQUE`
ORDER BY `TABLE_NAME`, `INDEX_NAME`;



-- 7.11 TESTES DAS RESTRIÇÕES (inserções propositalmente inválidas).
-- -----------------------------------------------------------------------------
-- As consultas anteriores confirmam que os dados válidos estão corretos. Os
-- comandos abaixo fazem o caminho inverso: tentam gravar dados inválidos para
-- demonstrar que o banco os rejeita. Cada um foi executado no MySQL 8.0 e a
-- mensagem devolvida pelo SGBD está registrada ao lado.
--
-- Estão comentados porque qualquer um deles interrompe a execução do script.
-- Para executá-los, remova os comentários de um bloco por vez, ou salve-os em
-- arquivo separado e rode com a opção --force:
--   mysql -u root -p --force < testes_restricoes.sql
--
-- Esta seção corresponde ao quadro da seção 6.3 da documentação.

-- T1. CPF com letras -> CHECK chk_usuario_cpf_digitos
-- INSERT INTO `usuario` (`nome`,`cpf`,`email`,`senha_hash`,`tipo`)
--   VALUES ('Teste','ABC12345678','t1@teste.com','hash','produtor');
--   ERROR 3819: Check constraint 'chk_usuario_cpf_digitos' is violated.

-- T2. CPF já cadastrado -> UNIQUE uq_usuario_cpf
-- INSERT INTO `usuario` (`nome`,`cpf`,`email`,`senha_hash`,`tipo`)
--   VALUES ('Teste','01987654321','t2@teste.com','hash','produtor');
--   ERROR 1062: Duplicate entry '01987654321' for key 'usuario.uq_usuario_cpf'.

-- T3. Perfil fora do domínio -> ENUM da coluna `tipo`
-- INSERT INTO `usuario` (`nome`,`cpf`,`email`,`senha_hash`,`tipo`)
--   VALUES ('Teste','12345678901','t3@teste.com','hash','gerente');
--   ERROR 1265: Data truncated for column 'tipo' at row 1.
--   (O SQL_MODE estrito, definido no início deste script, transforma em erro o
--    que de outro modo seria apenas um aviso com gravação de valor vazio.)

-- T4. E-mail sem formato mínimo -> CHECK chk_usuario_email_formato
-- INSERT INTO `usuario` (`nome`,`cpf`,`email`,`senha_hash`,`tipo`)
--   VALUES ('Teste','12345678902','semarroba','hash','produtor');
--   ERROR 3819: Check constraint 'chk_usuario_email_formato' is violated.

-- T5. Área vinculada a um técnico -> TRIGGER trg_area_cultivo_bi_produtor (RF03)
-- INSERT INTO `area_cultivo` (`nome`,`localizacao`,`cultura`,`data_plantio`,`tamanho`,`id_produtor`)
--   VALUES ('Talhão teste','POINT(-54.8 -22.2)','Soja','2026-01-10',50.00,7);
--   ERROR 1644: RF03: a area de cultivo deve pertencer a um usuario do tipo produtor.
--   (O usuário 7 é do tipo 'tecnico'. Esta é a regra que o CHECK não consegue
--    expressar no MySQL, por exigir subconsulta em outra tabela.)

-- T6. Área com tamanho negativo -> CHECK chk_area_tamanho_positivo
-- INSERT INTO `area_cultivo` (`nome`,`localizacao`,`cultura`,`data_plantio`,`tamanho`,`id_produtor`)
--   VALUES ('Talhão teste','POINT(-54.8 -22.2)','Soja','2026-01-10',-5.00,1);
--   ERROR 3819: Check constraint 'chk_area_tamanho_positivo' is violated.

-- T7. Cobertura de nuvens de 150% -> CHECK chk_imagem_perc_nuvens
-- INSERT INTO `imagem_satelite`
--   (`satelite`,`data_aquisicao`,`resolucao`,`perc_nuvens`,`localizacao`,`url_arquivo`,`id_area`)
--   VALUES ('Sentinel-2A','2026-09-01',10.00,150.00,'POLYGON(...)','s3://teste.tif',1);
--   ERROR 3819: Check constraint 'chk_imagem_perc_nuvens' is violated.

-- T8. Imagem em área inexistente -> FOREIGN KEY fk_imagem_satelite_area_cultivo
-- INSERT INTO `imagem_satelite`
--   (`satelite`,`data_aquisicao`,`resolucao`,`perc_nuvens`,`localizacao`,`url_arquivo`,`id_area`)
--   VALUES ('Sentinel-2A','2026-09-01',10.00,5.00,'POLYGON(...)','s3://teste.tif',9999);
--   ERROR 1452: Cannot add or update a child row: a foreign key constraint fails
--               (fk_imagem_satelite_area_cultivo).

-- T9. Mesma cena registrada duas vezes -> UNIQUE uq_imagem_area_satelite_data
-- INSERT INTO `imagem_satelite`
--   (`satelite`,`data_aquisicao`,`resolucao`,`perc_nuvens`,`localizacao`,`url_arquivo`,`id_area`)
--   VALUES ('Landsat-9','2025-11-01',30.00,4.00,'POLYGON(...)','s3://teste.tif',1);
--   ERROR 1062: Duplicate entry '1-Landsat-9-2025-11-01'
--               for key 'imagem_satelite.uq_imagem_area_satelite_data'.

-- T10. Índice com valor acima de 1 -> CHECK chk_indice_faixa_valores
-- INSERT INTO `indice_vegetacao` (`tipo`,`valor_medio`,`valor_min`,`valor_max`,`data`,`id_imagem`)
--   VALUES ('SAVI',0.5000,0.1000,1.5000,'2026-09-01',1);
--   ERROR 3819: Check constraint 'chk_indice_faixa_valores' is violated.

-- T11. Mínimo maior que o médio -> CHECK chk_indice_ordem_valores
-- INSERT INTO `indice_vegetacao` (`tipo`,`valor_medio`,`valor_min`,`valor_max`,`data`,`id_imagem`)
--   VALUES ('SAVI',0.2000,0.9000,0.9500,'2026-09-01',1);
--   ERROR 3819: Check constraint 'chk_indice_ordem_valores' is violated.

-- T12. Mesmo índice calculado duas vezes para a imagem -> UNIQUE uq_indice_imagem_tipo
-- INSERT INTO `indice_vegetacao` (`tipo`,`valor_medio`,`valor_min`,`valor_max`,`data`,`id_imagem`)
--   VALUES ('NDVI',0.5000,0.1000,0.9000,'2026-09-01',1);
--   ERROR 1062: Duplicate entry '1-NDVI' for key 'indice_vegetacao.uq_indice_imagem_tipo'.

-- T13. Avaliação referindo imagem E índice -> CHECK chk_avaliacao_alvo_exclusivo (RF08)
-- INSERT INTO `avaliacao` (`nota`,`comentario`,`data`,`id_usuario`,`id_imagem`,`id_indice`)
--   VALUES (5,'Teste','2026-09-01',1,1,1);
--   ERROR 3819: Check constraint 'chk_avaliacao_alvo_exclusivo' is violated.

-- T14. Avaliação sem alvo algum -> CHECK chk_avaliacao_alvo_exclusivo (RF08)
-- INSERT INTO `avaliacao` (`nota`,`comentario`,`data`,`id_usuario`,`id_imagem`,`id_indice`)
--   VALUES (5,'Teste','2026-09-01',1,NULL,NULL);
--   ERROR 3819: Check constraint 'chk_avaliacao_alvo_exclusivo' is violated.
--   (T13 e T14 demonstram os dois lados do RF08: a avaliação não pode ter dois
--    alvos nem ficar sem nenhum.)

-- T15. Nota fora da escala -> CHECK chk_avaliacao_nota
-- INSERT INTO `avaliacao` (`nota`,`comentario`,`data`,`id_usuario`,`id_imagem`,`id_indice`)
--   VALUES (9,'Teste','2026-09-01',1,44,NULL);
--   ERROR 3819: Check constraint 'chk_avaliacao_nota' is violated.

-- T16. Excluir produtor que ainda possui áreas -> FK ON DELETE RESTRICT
-- DELETE FROM `usuario` WHERE `id_usuario` = 1;
--   ERROR 1451: Cannot delete or update a parent row: a foreign key constraint
--               fails (fk_area_cultivo_usuario).
--   (Demonstra a ação referencial da seção 5.3.1: o histórico do produtor é
--    preservado, ao contrário do CASCADE usado nas imagens e nos índices.)

-- T17. Transferir área para um administrador -> TRIGGER trg_area_cultivo_bu_produtor
-- UPDATE `area_cultivo` SET `id_produtor` = 11 WHERE `id_area` = 1;
--   ERROR 1644: RF03: a area de cultivo deve pertencer a um usuario do tipo produtor.
--   (O usuário 11 é do tipo 'administrador'. Confirma que o RF03 é garantido
--    tanto na inserção quanto na alteração.)


-- =============================================================================
-- 8. BACKUP E RESTAURAÇÃO
-- =============================================================================
-- Os comandos abaixo são executados no terminal do sistema operacional, e não
-- dentro do cliente SQL. Estão comentados para não interferir neste script.
--
-- 8.1 BACKUP completo (estrutura + dados + gatilhos + visões):
--   mysqldump -u root -p --single-transaction --routines --triggers --events \
--             --set-gtid-purged=OFF --databases monitoramento_agricola \
--             > backup_monitoramento_agricola.sql
--
--   --single-transaction ... backup consistente sem travar as tabelas (InnoDB)
--   --routines/--triggers/--events ... inclui gatilhos e demais objetos
--   --set-gtid-purged=OFF .. evita erro de GTID ao restaurar no mesmo servidor
--   --databases ............ inclui CREATE DATABASE e USE no arquivo gerado
--
-- 8.2 BACKUP apenas da estrutura (sem dados):
--   mysqldump -u root -p --no-data --routines --triggers \
--             --set-gtid-purged=OFF --databases monitoramento_agricola \
--             > estrutura_monitoramento_agricola.sql
--
-- 8.3 BACKUP apenas dos dados (sem estrutura):
--   mysqldump -u root -p --no-create-info --set-gtid-purged=OFF \
--             --databases monitoramento_agricola > dados_monitoramento_agricola.sql
--
-- 8.4 RESTAURAÇÃO (o arquivo do item 8.1 já contém CREATE DATABASE e USE):
--   mysql -u root -p < backup_monitoramento_agricola.sql
--
-- 8.5 Conferência após a restauração (executar no cliente SQL):
--   USE monitoramento_agricola;
--   SELECT COUNT(*) FROM imagem_satelite;      -- deve retornar 45
--   SELECT COUNT(*) FROM indice_vegetacao;     -- deve retornar 120
--   SHOW TRIGGERS;                             -- deve listar 2 gatilhos
--
-- 8.6 Pelo MySQL Workbench, o mesmo procedimento está em:
--   Server > Data Export    (backup)
--   Server > Data Import    (restauração)
--
-- =============================================================================
-- FIM DO SCRIPT
-- =============================================================================

