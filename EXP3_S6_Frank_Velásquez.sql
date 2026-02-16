/*
================================================================================
Procesamiento: sp_almacenar_pago_cero
================================================================================
Descripción:
Almacena en la tabla GASTO_COMUN_PAGO_CERO la información de un departamento
que no ha realizado el pago de gastos comunes.

Parámetros:
  p_anno_mes_pcgc    (IN) - Período de cobro (formato YYYYMM)
  p_id_edif          (IN) - ID del edificio
  p_nombre_edif      (IN) - Nombre del edificio
  p_run_adm          (IN) - RUN del administrador (formato RUN-DV)
  p_nombre_adm       (IN) - Nombre completo del administrador
  p_nro_depto        (IN) - Número del departamento
  p_run_resp         (IN) - RUN del responsable del pago (formato RUN-DV)
  p_nombre_resp      (IN) - Nombre completo del responsable
  p_valor_multa      (IN) - Valor de la multa a aplicar
  p_observacion      (IN) - Observación sobre el estado del pago y corte
================================================================================
*/
CREATE OR REPLACE PROCEDURE sp_almacenar_pago_cero(
    p_anno_mes_pcgc IN NUMBER,
    p_id_edif IN NUMBER,
    p_nombre_edif IN VARCHAR2,
    p_run_adm IN VARCHAR2,
    p_nombre_adm IN VARCHAR2,
    p_nro_depto IN NUMBER,
    p_run_resp IN VARCHAR2,
    p_nombre_resp IN VARCHAR2,
    p_valor_multa IN NUMBER,
    p_observacion IN VARCHAR2
) IS
BEGIN
    INSERT INTO GASTO_COMUN_PAGO_CERO (
        anno_mes_pcgc,
        id_edif,
        nombre_edif,
        run_administrador,
        nombre_admnistrador,
        nro_depto,
        run_responsable_pago_gc,
        nombre_responsable_pago_gc,
        valor_multa_pago_cero,
        observacion
    ) VALUES (
        p_anno_mes_pcgc,
        p_id_edif,
        p_nombre_edif,
        p_run_adm,
        p_nombre_adm,
        p_nro_depto,
        p_run_resp,
        p_nombre_resp,
        p_valor_multa,
        p_observacion
    );
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Registro almacenado: Edificio ' || p_nombre_edif || 
                         ', Depto ' || p_nro_depto);
    
EXCEPTION
    -- ExcepciÃ³n cuando se intenta insertar un registro duplicado
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: El registro ya existe para el perÃ­odo ' || 
                            p_anno_mes_pcgc || ', edificio ' || p_id_edif || 
                            ', depto ' || p_nro_depto);
        ROLLBACK;
        
    -- ExcepciÃ³n para cualquier otro error
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR inesperado al almacenar pago cero: ' || SQLERRM);
        ROLLBACK;
        RAISE;
END sp_almacenar_pago_cero;
/


/*
================================================================================
Procesamiento: sp_procesar_pagos_cero
================================================================================
Descripción:
Procedimiento principal que identifica los departamentos que no han pagado
sus gastos comunes en los últimos dos períodos de cobro.

Parámetros:
  p_anno_mes_procesar (IN) - Período de cobro a procesar (formato YYYYMM)
  p_valor_uf          (IN) - Valor de la UF para el cálculo de multas
================================================================================
*/
CREATE OR REPLACE PROCEDURE sp_procesar_pagos_cero(
    p_anno_mes_procesar IN NUMBER,
    p_valor_uf IN NUMBER
) IS
    -- Variables para el período anterior
    v_anno_mes_anterior NUMBER;
    v_anno_anterior NUMBER;
    v_mes_anterior NUMBER;
    
    -- Variables para la información del departamento
    v_id_edif NUMBER;
    v_nombre_edif VARCHAR2(50);
    v_numrun_adm NUMBER;
    v_dvrun_adm VARCHAR2(1);
    v_nombre_adm VARCHAR2(200);
    v_nro_depto NUMBER;
    v_numrun_resp NUMBER;
    v_dvrun_resp VARCHAR2(1);
    v_nombre_resp VARCHAR2(200);
    v_fecha_pago DATE;
    
    -- Variables para el cálculo
    v_cant_periodos_sin_pago NUMBER;
    v_valor_multa NUMBER;
    v_observacion VARCHAR2(80);
    v_run_adm_formato VARCHAR2(20);
    v_run_resp_formato VARCHAR2(20);
    v_registros_procesados NUMBER := 0;
    
    -- Cursor para obtener departamentos sin pago en el período anterior
    CURSOR c_deptos_sin_pago IS
        SELECT 
            gc.id_edif,
            e.nombre_edif,
            a.numrun_adm,
            a.dvrun_adm,
            a.pnombre_adm || ' ' || 
            NVL(a.snombre_adm || ' ', '') || 
            a.appaterno_adm || ' ' || 
            NVL(a.apmaterno_adm, '') AS nombre_completo_adm,
            gc.nro_depto,
            r.numrun_rpgc,
            r.dvrun_rpgc,
            r.pnombre_rpgc || ' ' || 
            NVL(r.snombre_rpgc || ' ', '') || 
            r.appaterno_rpgc || ' ' || 
            NVL(r.apmaterno_rpgc, '') AS nombre_completo_resp,
            gc.fecha_pago_gc
        FROM GASTO_COMUN gc
        INNER JOIN EDIFICIO e ON gc.id_edif = e.id_edif
        INNER JOIN ADMINISTRADOR a ON e.numrun_adm = a.numrun_adm
        INNER JOIN RESPONSABLE_PAGO_GASTO_COMUN r ON gc.numrun_rpgc = r.numrun_rpgc
        WHERE gc.anno_mes_pcgc = v_anno_mes_anterior
          -- Filtro: departamentos SIN ningún pago registrado
          AND NOT EXISTS (
              SELECT 1
              FROM PAGO_GASTO_COMUN pgc
              WHERE pgc.anno_mes_pcgc = gc.anno_mes_pcgc
                AND pgc.id_edif = gc.id_edif
                AND pgc.nro_depto = gc.nro_depto
          )
        ORDER BY e.nombre_edif, gc.nro_depto;
    
BEGIN
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('INICIO PROCESO: Generación de información de pagos cero');
    DBMS_OUTPUT.PUT_LINE('Período a procesar: ' || p_anno_mes_procesar);
    DBMS_OUTPUT.PUT_LINE('Valor UF: $' || TO_CHAR(p_valor_uf, '999,999'));
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    
    /*
    ============================================================================
    PASO 1: Calcular el período anterior al que se está procesando
    ============================================================================
    */
    v_anno_anterior := TRUNC(p_anno_mes_procesar / 100);
    v_mes_anterior := MOD(p_anno_mes_procesar, 100);
    
    -- Si el mes es enero, retroceder al año anterior, mes diciembre
    IF v_mes_anterior = 1 THEN
        v_anno_anterior := v_anno_anterior - 1;
        v_mes_anterior := 12;
    ELSE
        v_mes_anterior := v_mes_anterior - 1;
    END IF;
    
    v_anno_mes_anterior := v_anno_anterior * 100 + v_mes_anterior;
    
    DBMS_OUTPUT.PUT_LINE('Período anterior calculado: ' || v_anno_mes_anterior);
    DBMS_OUTPUT.PUT_LINE('');
    
    /*
    ============================================================================
    PASO 2: Limpiar registros previos del período a procesar
    ============================================================================
    */
    DELETE FROM GASTO_COMUN_PAGO_CERO
    WHERE anno_mes_pcgc = p_anno_mes_procesar;
    
    DBMS_OUTPUT.PUT_LINE('Registros previos eliminados: ' || SQL%ROWCOUNT);
    COMMIT;
    
    /*
    ============================================================================
    PASO 3: Procesar cada departamento sin pago
    ============================================================================
    */
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Procesando departamentos sin pago...');
    DBMS_OUTPUT.PUT_LINE('');
    
    FOR rec IN c_deptos_sin_pago LOOP
        v_id_edif := rec.id_edif;
        v_nombre_edif := rec.nombre_edif;
        v_numrun_adm := rec.numrun_adm;
        v_dvrun_adm := rec.dvrun_adm;
        v_nombre_adm := rec.nombre_completo_adm;
        v_nro_depto := rec.nro_depto;
        v_numrun_resp := rec.numrun_rpgc;
        v_dvrun_resp := rec.dvrun_rpgc;
        v_nombre_resp := rec.nombre_completo_resp;
        v_fecha_pago := rec.fecha_pago_gc;
        
        /*
        ========================================================================
        PASO 4: Contar cuántos períodos consecutivos no ha pagado
        ========================================================================
        */
        SELECT COUNT(*)
        INTO v_cant_periodos_sin_pago
        FROM GASTO_COMUN gc
        WHERE gc.id_edif = v_id_edif
          AND gc.nro_depto = v_nro_depto
          AND gc.anno_mes_pcgc <= v_anno_mes_anterior
          AND NOT EXISTS (
              SELECT 1
              FROM PAGO_GASTO_COMUN pgc
              WHERE pgc.anno_mes_pcgc = gc.anno_mes_pcgc
                AND pgc.id_edif = gc.id_edif
                AND pgc.nro_depto = gc.nro_depto
          );
        
        /*
        ========================================================================
        PASO 5: Calcular multa y generar observación según períodos sin pago
        ========================================================================
        */
        IF v_cant_periodos_sin_pago = 1 THEN
            -- Primera mora: multa de 2 UF
            v_valor_multa := ROUND(2 * p_valor_uf);
            v_observacion := 'Se realizará el corte del combustible y agua a contar del ' || 
                           TO_CHAR(v_fecha_pago, 'DD/MM/YYYY');
            
            DBMS_OUTPUT.PUT_LINE('  - Edificio: ' || v_nombre_edif || 
                               ', Depto: ' || v_nro_depto || 
                               ' -> 1 período sin pago, multa: $' || 
                               TO_CHAR(v_valor_multa, '999,999,999'));
            
        ELSIF v_cant_periodos_sin_pago >= 2 THEN
            -- Reincidencia: multa de 4 UF
            v_valor_multa := ROUND(4 * p_valor_uf);
            v_observacion := 'Se realizará el corte del combustible y agua a contar del ' || 
                           TO_CHAR(v_fecha_pago, 'DD/MM/YYYY');
            
            DBMS_OUTPUT.PUT_LINE('  - Edificio: ' || v_nombre_edif || 
                               ', Depto: ' || v_nro_depto || 
                               ' -> ' || v_cant_periodos_sin_pago || 
                               ' períodos sin pago, multa: $' || 
                               TO_CHAR(v_valor_multa, '999,999,999'));
        ELSE
            v_valor_multa := 0;
            v_observacion := 'Sin observaciones';
        END IF;
        
        /*
        ========================================================================
        PASO 6: Formatear RUNs para almacenamiento
        ========================================================================
        */       
        v_run_adm_formato := TO_CHAR(v_numrun_adm, 'FM999G999G999') || '-' || v_dvrun_adm;
        v_run_resp_formato := TO_CHAR(v_numrun_resp, 'FM999G999G999') || '-' || v_dvrun_resp;
        /*
        ========================================================================
        PASO 7: Almacenar información en GASTO_COMUN_PAGO_CERO
        ========================================================================
        */
        sp_almacenar_pago_cero(
            p_anno_mes_pcgc => p_anno_mes_procesar,
            p_id_edif => v_id_edif,
            p_nombre_edif => v_nombre_edif,
            p_run_adm => v_run_adm_formato,
            p_nombre_adm => v_nombre_adm,
            p_nro_depto => v_nro_depto,
            p_run_resp => v_run_resp_formato,
            p_nombre_resp => v_nombre_resp,
            p_valor_multa => v_valor_multa,
            p_observacion => v_observacion
        );
        
        /*
        ========================================================================
        PASO 8: Actualizar multa en GASTO_COMUN para el período actual
        ========================================================================
        */
        UPDATE GASTO_COMUN
        SET multa_gc = v_valor_multa,
            -- Recalcular el monto total sumando la multa
            monto_total_gc = prorrateado_gc + 
                           fondo_reserva_gc + 
                           agua_individual_gc + 
                           combustible_individual_gc + 
                           NVL(lavanderia_gc, 0) + 
                           NVL(evento_gc, 0) + 
                           NVL(servicio_gc, 0) + 
                           NVL(monto_atrasado_gc, 0) + 
                           v_valor_multa
        WHERE anno_mes_pcgc = p_anno_mes_procesar
          AND id_edif = v_id_edif
          AND nro_depto = v_nro_depto;
        
        COMMIT;
        
        -- Incrementar contador
        v_registros_procesados := v_registros_procesados + 1;
        
    END LOOP;
    
    /*
    ============================================================================
    PASO 9: Resumen del proceso
    ============================================================================
    */
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('FIN PROCESO');
    DBMS_OUTPUT.PUT_LINE('Registros procesados: ' || v_registros_procesados);
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    
EXCEPTION
    -- Excepción cuando no se encuentran datos
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: No se encontraron datos para procesar');
        ROLLBACK;
        
    -- Excepción para cualquier otro error
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR inesperado en el proceso: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('CÃ³digo de error: ' || SQLCODE);
        ROLLBACK;
        RAISE;
END sp_procesar_pagos_cero;
/

/*
================================================================================
Consultas de verificación
================================================================================
*/

-- Activar salida de mensajes en consola
SET SERVEROUTPUT ON;

-- Ejecutar el procedimiento para mayo 2026 con UF de $29.509
BEGIN
    sp_procesar_pagos_cero(
        p_anno_mes_procesar => 202605,  -- Mayo 2026
        p_valor_uf => 29509              -- Valor UF en pesos chilenos
    );
END;
/

-- ================================================================================
-- Verificación 1: Departamentos con pago cero (GASTO_COMUN_PAGO_CERO)
-- ================================================================================

SELECT 
    anno_mes_pcgc AS "PERIODO",
    id_edif AS "ID_EDIF",
    nombre_edif AS "EDIFICIO",
    run_administrador AS "RUN_ADM",
    nombre_admnistrador AS "ADMINISTRADOR",
    nro_depto AS "NRO_DEPTO",
    run_responsable_pago_gc AS "RUN_RESP",
    nombre_responsable_pago_gc AS "RESPONSABLE",
    valor_multa_pago_cero AS "MULTA",
    observacion AS "OBSERVACION"
FROM GASTO_COMUN_PAGO_CERO
WHERE anno_mes_pcgc = 202605
ORDER BY nombre_edif, nro_depto;

-- ================================================================================
-- Verificación 2: Multas actualizadas en gastos comunes (GASTO_COMUN)
-- ================================================================================

SELECT 
    gc.anno_mes_pcgc AS "PERIODO",
    gc.id_edif AS "ID_EDIF",
    e.nombre_edif AS "EDIFICIO",
    gc.nro_depto AS "NRO_DEPTO",
    gc.fecha_desde_gc AS "FECHA_DESDE",
    gc.fecha_hasta_gc AS "FECHA_HASTA",
    gc.multa_gc AS "MULTA",
    gc.monto_total_gc AS "MONTO_TOTAL"
FROM GASTO_COMUN gc
INNER JOIN EDIFICIO e ON gc.id_edif = e.id_edif
WHERE gc.anno_mes_pcgc = 202605
  AND gc.multa_gc > 0
ORDER BY e.nombre_edif, gc.nro_depto;

-- ================================================================================
-- Verificación 3: Estadísticas del proceso
-- ================================================================================

SELECT 
    'Total departamentos sin pago' AS "CONCEPTO",
    COUNT(*) AS "CANTIDAD"
FROM GASTO_COMUN_PAGO_CERO
WHERE anno_mes_pcgc = 202605
UNION ALL
SELECT 
    'Multas de 2 UF (1 perÃ­odo)',
    COUNT(*)
FROM GASTO_COMUN_PAGO_CERO
WHERE anno_mes_pcgc = 202605
  AND valor_multa_pago_cero = 59018
UNION ALL
SELECT 
    'Multas de 4 UF (2+ perÃ­odos)',
    COUNT(*)
FROM GASTO_COMUN_PAGO_CERO
WHERE anno_mes_pcgc = 202605
  AND valor_multa_pago_cero = 118036;
