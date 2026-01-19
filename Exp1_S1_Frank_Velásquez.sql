
----------------------------------------------------------------
-- :::::::::::::::::: CASO 1 :::::::::::::::::::::::::::::::::::
----------------------------------------------------------------

----------------------------------------------------------------
-- Datos del cliente (rut)
----------------------------------------------------------------

VAR b_run_cliente VARCHAR2(15)

----------------------------------------------------------------
-- Variables BIND
----------------------------------------------------------------
VAR b_peso_normal NUMBER
VAR b_extra_tramo_1 NUMBER
VAR b_extra_tramo_2 NUMBER
VAR b_extra_tramo_3 NUMBER

----------------------------------------------------------------
-- Asignación de valores
----------------------------------------------------------------
-- KAREN SOFIA PRADENAS MANDIOLA 21242003-4
-- SILVANA MARTINA VALENZUELA DUARTE 22176845-2
-- DENISSE ALICIA DIAZ MIRANDA 18858542-6
-- AMANDA ROMINA LIZANA MARAMBIO 22558061-8
-- LUIS CLAUDIO LUNA JORQUERA 21300628-2

EXEC :b_run_cliente := '21242003-4'

EXEC :b_peso_normal   := 1200
EXEC :b_extra_tramo_1 := 100
EXEC :b_extra_tramo_2 := 300
EXEC :b_extra_tramo_3 := 550


----------------------------------------------------------------
-- BLOQUE PL/SQL
----------------------------------------------------------------

DECLARE
    ----------------------------------------------------------------
    -- Datos del cliente
    ----------------------------------------------------------------
    v_nro_cliente       CLIENTE.nro_cliente%TYPE;
    v_run_cliente       CLIENTE.numrun%TYPE;
    v_dv_run            CLIENTE.dvrun%TYPE;
    v_nombre_cliente    VARCHAR2(50);
    v_tipo_cliente      TIPO_CLIENTE.nombre_tipo_cliente%TYPE;

    ----------------------------------------------------------------
    -- Créditos
    ----------------------------------------------------------------
    v_monto_total       NUMBER := 0;

    ----------------------------------------------------------------
    -- Cálculo de pesos
    ----------------------------------------------------------------
    v_pesos_normales    NUMBER := 0;
    v_pesos_extra       NUMBER := 0;
    v_valor_extra       NUMBER := 0;
    v_total_pesos       NUMBER := 0;

BEGIN
    ----------------------------------------------------------------
    -- 1. Obtener datos del cliente a partir del RUN
    ----------------------------------------------------------------
    SELECT c.nro_cliente,
           c.numrun,
           c.dvrun,
           c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno  ,
           tc.nombre_tipo_cliente
    INTO   v_nro_cliente,
           v_run_cliente,
           v_dv_run,
           v_nombre_cliente,
           v_tipo_cliente
    FROM   cliente c
           JOIN tipo_cliente tc
             ON c.cod_tipo_cliente = tc.cod_tipo_cliente
    WHERE  c.numrun || '-' || c.dvrun = :b_run_cliente;

    ----------------------------------------------------------------
    -- 2. Obtener monto total de créditos del año anterior
    ----------------------------------------------------------------
    SELECT NVL(SUM(monto_solicitado),0)
    INTO   v_monto_total
    FROM   credito_cliente
    WHERE  nro_cliente = v_nro_cliente
    AND    EXTRACT(YEAR FROM fecha_solic_cred) =
           EXTRACT(YEAR FROM SYSDATE) - 1;

    ----------------------------------------------------------------
    -- 3. Cálculo de pesos normales
    ----------------------------------------------------------------
    v_pesos_normales :=
        TRUNC(v_monto_total / 100000) * :b_peso_normal;

    ----------------------------------------------------------------
    -- 4. Cálculo de pesos extra (solo INDEPENDIENTE)
    ----------------------------------------------------------------
    IF v_tipo_cliente = 'Trabajadores independientes' THEN

        IF v_monto_total < 1000000 THEN
            v_valor_extra := :b_extra_tramo_1;

        ELSIF v_monto_total <= 3000000 THEN
            v_valor_extra := :b_extra_tramo_2;

        ELSE
            v_valor_extra := :b_extra_tramo_3;
        END IF;

        v_pesos_extra :=
            TRUNC(v_monto_total / 100000) * v_valor_extra;
    END IF;

    ----------------------------------------------------------------
    -- 5. Total de pesos TODOSUMA
    ----------------------------------------------------------------
    v_total_pesos := v_pesos_normales + v_pesos_extra;

    ----------------------------------------------------------------
    -- 6. Eliminar registro previo del cliente
    ----------------------------------------------------------------
    DELETE FROM cliente_todosuma
    WHERE nro_cliente = v_nro_cliente;

    ----------------------------------------------------------------
    -- 7. Insertar resultado en CLIENTE_TODOSUMA
    ----------------------------------------------------------------
    INSERT INTO cliente_todosuma (
        nro_cliente,
        run_cliente,
        nombre_cliente,
        tipo_cliente,
        monto_solic_creditos,
        monto_pesos_todosuma
    )
    VALUES (
        v_nro_cliente,
        TO_CHAR(v_run_cliente,'FM999G999G999','NLS_NUMERIC_CHARACTERS = '',.''') || '-' || v_dv_run,        
        v_nombre_cliente,
        v_tipo_cliente,
        v_monto_total,
        v_total_pesos
    );

    ----------------------------------------------------------------
    -- 8. Confirmar transacción
    ----------------------------------------------------------------
    COMMIT;

    ----------------------------------------------------------------
    -- 9. Salida de control
    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('RUN CLIENTE      : ' || :b_run_cliente);
    DBMS_OUTPUT.PUT_LINE('MONTO TOTAL     : ' || v_monto_total);
    DBMS_OUTPUT.PUT_LINE('PESOS NORMALES  : ' || v_pesos_normales);
    DBMS_OUTPUT.PUT_LINE('PESOS EXTRA     : ' || v_pesos_extra);
    DBMS_OUTPUT.PUT_LINE('TOTAL TODOSUMA  : ' || v_total_pesos);

EXCEPTION
    ----------------------------------------------------------------
    -- Manejo de errores
    ----------------------------------------------------------------
    
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Cliente no existe');

    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

----------------------------------------------------------------
-- Verificar que haya sido guardado en tabla nueva
----------------------------------------------------------------

SELECT *
FROM cliente_todosuma
WHERE run_cliente =
      TO_CHAR(
        TO_NUMBER(SUBSTR(:b_run_cliente, 1, INSTR(:b_run_cliente, '-') - 1)),
        'FM999G999G999',
        'NLS_NUMERIC_CHARACTERS = '',.'''
      ) || '-' ||
      SUBSTR(:b_run_cliente, INSTR(:b_run_cliente, '-') + 1);


------------------------------------------------------------
-- ::::::::::::::::::::::  CASO 2  :::::::::::::::::::::::::
------------------------------------------------------------

------------------------------------------------------------
-- Activar salida por consola
------------------------------------------------------------
SET SERVEROUTPUT ON;

------------------------------------------------------------
-- Variables BIND
------------------------------------------------------------

VAR b_nro_cliente NUMBER
VAR b_nro_solicitud NUMBER
VAR b_cant_cuotas NUMBER

----------------------------------------------------------------
-- Asignación de valores
----------------------------------------------------------------

EXEC :b_nro_cliente   := 67
EXEC :b_nro_solicitud := 3004
EXEC :b_cant_cuotas   := 1


----------------------------------------------------------------
-- BLOQUE PL/SQL
----------------------------------------------------------------


DECLARE
    ------------------------------------------------------------
    -- Datos del crédito
    ------------------------------------------------------------
    v_tipo_credito        CREDITO.nombre_credito%TYPE;
    v_valor_ultima_cuota  CUOTA_CREDITO_CLIENTE.valor_cuota%TYPE;
    v_fecha_ult_venc      CUOTA_CREDITO_CLIENTE.fecha_venc_cuota%TYPE;
    v_num_ult_cuota       CUOTA_CREDITO_CLIENTE.nro_cuota%TYPE;
    v_cod_tipo_credito    CREDITO.cod_credito%TYPE;

    ------------------------------------------------------------
    -- Cálculo nuevas cuotas
    ------------------------------------------------------------
    v_tasa_interes        NUMBER := 0;
    v_valor_nueva_cuota   NUMBER := 0;

    ------------------------------------------------------------
    -- Control
    ------------------------------------------------------------
    v_total_creditos_ant  NUMBER := 0;

BEGIN
    ------------------------------------------------------------
    -- 1. Obtener tipo de crédito
    ------------------------------------------------------------
    SELECT tc.cod_credito
    INTO   v_cod_tipo_credito
    FROM   credito_cliente cc
           JOIN credito tc
             ON cc.cod_credito = tc.cod_credito
    WHERE  cc.nro_solic_credito = :b_nro_solicitud
    AND    cc.nro_cliente       = :b_nro_cliente;

    ------------------------------------------------------------
    -- 2. Obtener última cuota del crédito
    ------------------------------------------------------------
    SELECT nro_cuota,
        fecha_venc_cuota,
        valor_cuota
    INTO   v_num_ult_cuota,
        v_fecha_ult_venc,
        v_valor_ultima_cuota
    FROM   cuota_credito_cliente
    WHERE  nro_solic_credito = :b_nro_solicitud
    AND    nro_cuota = (
            SELECT MAX(nro_cuota)
            FROM   cuota_credito_cliente
            WHERE  nro_solic_credito = :b_nro_solicitud);

    ------------------------------------------------------------
    -- 3. Determinar tasa de interés según tipo de crédito
    ------------------------------------------------------------
    IF v_cod_tipo_credito = 1 THEN --HIPOTECARIO
        IF :b_cant_cuotas = 1 THEN
            v_tasa_interes := 0;
        ELSE
            v_tasa_interes := 0.005;
        END IF;

    ELSIF v_cod_tipo_credito = 2 THEN --CONSUMO
        v_tasa_interes := 0.01;

    ELSIF v_cod_tipo_credito = 3 THEN --AUTOMOTRIZ
        v_tasa_interes := 0.02;
    END IF;

    ------------------------------------------------------------
    -- 4. Generar nuevas cuotas postergadas
    ------------------------------------------------------------
    FOR i IN 1 .. :b_cant_cuotas LOOP

        v_num_ult_cuota := v_num_ult_cuota + 1;
        v_fecha_ult_venc := ADD_MONTHS(v_fecha_ult_venc, 1);

        v_valor_nueva_cuota :=
            v_valor_ultima_cuota +
            (v_valor_ultima_cuota * v_tasa_interes);

        INSERT INTO cuota_credito_cliente (
            nro_solic_credito,
            nro_cuota,
            fecha_venc_cuota,
            valor_cuota,
            fecha_pago_cuota,
            monto_pagado,
            saldo_por_pagar,
            cod_forma_pago
        )   
        VALUES (
            :b_nro_solicitud,
            v_num_ult_cuota,
            v_fecha_ult_venc,
            v_valor_nueva_cuota,
            NULL,
            NULL,
            NULL,
            NULL
        );
    END LOOP;

    ------------------------------------------------------------
    -- 5. Validar si el cliente tuvo más de un crédito el año anterior
    ------------------------------------------------------------
    SELECT COUNT(*)
    INTO   v_total_creditos_ant
    FROM   credito_cliente
    WHERE  nro_cliente = :b_nro_cliente
    AND    EXTRACT(YEAR FROM fecha_solic_cred) =
           EXTRACT(YEAR FROM SYSDATE) - 1;

    ------------------------------------------------------------
    -- 6. Condona última cuota original si corresponde
    ------------------------------------------------------------
    IF v_total_creditos_ant > 1 THEN
        UPDATE cuota_credito_cliente
        SET    fecha_pago_cuota   = fecha_venc_cuota,
               monto_pagado = valor_cuota
        WHERE  nro_solic_credito = :b_nro_solicitud
        AND    nro_cuota         = (
               SELECT MAX(nro_cuota)
               FROM   cuota_credito_cliente
               WHERE  nro_solic_credito = :b_nro_solicitud
               AND    fecha_pago_cuota IS NULL
        );
    END IF;

    ------------------------------------------------------------
    -- 7. Confirmar cambios
    ------------------------------------------------------------
    COMMIT;

    ------------------------------------------------------------
    -- 8. Mensaje de control
    ------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('Proceso CASO 2 ejecutado correctamente');
    DBMS_OUTPUT.PUT_LINE('Cliente       : ' || :b_nro_cliente);
    DBMS_OUTPUT.PUT_LINE('CrÃ©dito       : ' || :b_nro_solicitud);
    DBMS_OUTPUT.PUT_LINE('Cuotas nuevas : ' || :b_cant_cuotas);

EXCEPTION
    ----------------------------------------------------------------
    -- Manejo de errores
    ----------------------------------------------------------------
    
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Datos no encontrados');

    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

----------------------------------------------------------------
-- Verificar que haya sido guardado en tabla
----------------------------------------------------------------

SELECT *
FROM cuota_credito_cliente
WHERE nro_solic_credito = :b_nro_solicitud
ORDER BY nro_cuota;



