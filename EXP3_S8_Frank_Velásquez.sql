
-- ============================================================
-- PRY2206 SEMANA 8 - HOTEL LA ULTIMA OPORTUNIDAD
-- ============================================================

-- ==============================================================
-- CASO 1: TRIGGER trg_actualiza_total_consumos
--
-- Objetivo: mantener actualizado el monto total de consumos
-- por huesped en la tabla TOTAL_CONSUMOS ante cualquier
-- modificacion en la tabla CONSUMO.
-- ==============================================================

CREATE OR REPLACE TRIGGER trg_actualiza_total_consumos
AFTER INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        -- Sumar el nuevo monto al total existente del huesped
        UPDATE total_consumos
        SET    monto_consumos = monto_consumos + :NEW.monto
        WHERE  id_huesped     = :NEW.id_huesped;
        -- Si el huesped no tenia registro previo en TOTAL_CONSUMOS, crearlo
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO total_consumos (id_huesped, monto_consumos)
            VALUES (:NEW.id_huesped, :NEW.monto);
        END IF;

    ELSIF UPDATING THEN
        -- Ajustar el total aplicando la diferencia entre monto nuevo y anterior
        UPDATE total_consumos
        SET    monto_consumos = monto_consumos + (:NEW.monto - :OLD.monto)
        WHERE  id_huesped     = :NEW.id_huesped;

    ELSIF DELETING THEN
        -- Rebajar del total el monto del consumo eliminado
        UPDATE total_consumos
        SET    monto_consumos = monto_consumos - :OLD.monto
        WHERE  id_huesped     = :OLD.id_huesped;
    END IF;
END trg_actualiza_total_consumos;
/

-- --------------------------------------------------------------
-- Bloque de prueba: ejecuta las tres operaciones requeridas
-- para verificar que el trigger actualiza correctamente
-- la tabla TOTAL_CONSUMOS en cada caso.
-- --------------------------------------------------------------
DECLARE
    v_id consumo.id_consumo%TYPE;
BEGIN
    -- Obtener el ID siguiente al ultimo consumo registrado
    SELECT MAX(id_consumo) + 1 INTO v_id FROM consumo;

    -- Operacion 1: insertar nuevo consumo (huesped 340006, reserva 1587, $150)
    INSERT INTO consumo (id_consumo, id_reserva, id_huesped, monto)
    VALUES (v_id, 1587, 340006, 150);
    DBMS_OUTPUT.PUT_LINE('INSERT id=' || v_id);

    -- Operacion 2: eliminar consumo con ID 11473
    DELETE FROM consumo WHERE id_consumo = 11473;
    DBMS_OUTPUT.PUT_LINE('DELETE 11473');

    -- Operacion 3: actualizar monto del consumo 10688 a $95
    UPDATE consumo SET monto = 95 WHERE id_consumo = 10688;
    DBMS_OUTPUT.PUT_LINE('UPDATE 10688 -> 95');

    COMMIT;
END;
/

-- Verificacion de resultados tras las operaciones
SELECT * FROM total_consumos
WHERE  id_huesped IN (340003,340004,340006,340008,340009)
ORDER  BY id_huesped;

SELECT * FROM consumo
WHERE  id_huesped IN (340003,340004,340006,340008,340009)
ORDER  BY id_huesped, id_consumo;


-- ==============================================================
-- CASO 2: PACKAGE PKG_HOTEL
--
-- Contiene la funcion fn_monto_tours que calcula el total en
-- dolares de los tours contratados por un huesped
-- (valor_tour * num_personas). Retorna 0 si no tiene tours.
-- La variable publica g_monto_tours permite al procedimiento
-- principal reutilizar el ultimo valor calculado.
-- ==============================================================

CREATE OR REPLACE PACKAGE pkg_hotel AS
    g_monto_tours NUMBER;  -- variable publica opcional para el procedimiento principal
    FUNCTION fn_monto_tours(p_id IN huesped.id_huesped%TYPE) RETURN NUMBER;
END pkg_hotel;
/

CREATE OR REPLACE PACKAGE BODY pkg_hotel AS
    FUNCTION fn_monto_tours(p_id IN huesped.id_huesped%TYPE) RETURN NUMBER IS
        v NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(t.valor_tour * ht.num_personas), 0) INTO v
        FROM   huesped_tour ht JOIN tour t ON ht.id_tour = t.id_tour
        WHERE  ht.id_huesped = p_id;
        RETURN v;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END;
END pkg_hotel;
/


-- ==============================================================
-- FUNCION FN_AGENCIA
--
-- Retorna el nombre de la agencia de viajes asociada al huesped.
-- Si el huesped no tiene agencia registrada, registra el error
-- en REG_ERRORES y retorna 'NO REGISTRA AGENCIA'.
--
-- PRAGMA AUTONOMOUS_TRANSACTION: permite hacer DML en REG_ERRORES
-- sin interferir con la transaccion principal del procedimiento.
-- Las columnas del INSERT se preparan en variables locales para
-- evitar ORA-00984 (expresiones no permitidas en VALUES).
-- ==============================================================

CREATE OR REPLACE FUNCTION fn_agencia(p_id IN huesped.id_huesped%TYPE)
RETURN VARCHAR2 IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_ag  VARCHAR2(40);   -- nombre de la agencia
    v_er  NUMBER;         -- id del error (secuencia sq_error)
    v_sub VARCHAR2(200);  -- descripcion del subprograma para REG_ERRORES
    v_msg VARCHAR2(300);  -- mensaje de error para REG_ERRORES
BEGIN
    SELECT a.nom_agencia INTO v_ag
    FROM   huesped h JOIN agencia a ON h.id_agencia = a.id_agencia
    WHERE  h.id_huesped = p_id;
    RETURN v_ag;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        SELECT sq_error.NEXTVAL INTO v_er FROM dual;
        v_sub := 'Error en la funcion FN AGENCIA al recuperar la agencia del huesped con Id '
                 || TO_CHAR(p_id);
        v_msg := 'ORA-01403: No se ha encontrado ningun dato';
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (v_er, v_sub, v_msg);
        COMMIT;
        RETURN 'NO REGISTRA AGENCIA';
    WHEN OTHERS THEN
        SELECT sq_error.NEXTVAL INTO v_er FROM dual;
        v_sub := 'Error en la funcion FN AGENCIA al recuperar la agencia del huesped con Id '
                 || TO_CHAR(p_id);
        v_msg := SQLERRM;
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (v_er, v_sub, v_msg);
        COMMIT;
        RETURN 'NO REGISTRA AGENCIA';
END fn_agencia;
/


-- ==============================================================
-- FUNCION FN_CONSUMOS
--
-- Retorna el monto total de consumos del huesped consultando
-- la tabla TOTAL_CONSUMOS. Si no existe registro, registra
-- el error en REG_ERRORES y retorna 0.
-- Mismo patron que FN_AGENCIA: PRAGMA AUTONOMOUS_TRANSACTION
-- y variables locales para el INSERT en REG_ERRORES.
-- ==============================================================

CREATE OR REPLACE FUNCTION fn_consumos(p_id IN huesped.id_huesped%TYPE)
RETURN NUMBER IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_c   total_consumos.monto_consumos%TYPE;
    v_er  NUMBER;
    v_sub VARCHAR2(200);
    v_msg VARCHAR2(300);
BEGIN
    SELECT monto_consumos INTO v_c
    FROM   total_consumos
    WHERE  id_huesped = p_id;
    RETURN NVL(v_c, 0);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        SELECT sq_error.NEXTVAL INTO v_er FROM dual;
        v_sub := 'Error en la funcion FN CONSUMOS al recuperar los consumos del cliente con Id '
                 || TO_CHAR(p_id);
        v_msg := 'ORA-01403: No se ha encontrado ningun dato';
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (v_er, v_sub, v_msg);
        COMMIT;
        RETURN 0;
    WHEN OTHERS THEN
        SELECT sq_error.NEXTVAL INTO v_er FROM dual;
        v_sub := 'Error en la funcion FN CONSUMOS al recuperar los consumos del cliente con Id '
                 || TO_CHAR(p_id);
        v_msg := SQLERRM;
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (v_er, v_sub, v_msg);
        COMMIT;
        RETURN 0;
END fn_consumos;
/


-- ==============================================================
-- FUNCION FN_ALOJAMIENTO
--
-- Calcula el costo de alojamiento en dolares para el huesped:
-- SUM( (valor_habitacion + valor_minibar) * estadia )
-- considerando todas las habitaciones de su reserva.
-- Recibe la fecha como parametro para que el proceso sea
-- dinamico y no tenga fechas fijas en el codigo.
-- ==============================================================

CREATE OR REPLACE FUNCTION fn_alojamiento(
    p_id   IN huesped.id_huesped%TYPE,
    p_fech IN DATE
) RETURN NUMBER IS
    v NUMBER := 0;
BEGIN
    SELECT NVL(SUM((h.valor_habitacion + h.valor_minibar) * r.estadia), 0) INTO v
    FROM   reserva r
    JOIN   detalle_reserva dr ON r.id_reserva     = dr.id_reserva
    JOIN   habitacion h       ON dr.id_habitacion = h.id_habitacion
    WHERE  r.id_huesped            = p_id
    AND    (r.ingreso + r.estadia) = p_fech;  -- fecha salida = ingreso + dias estadia
    RETURN v;
EXCEPTION WHEN OTHERS THEN RETURN 0;
END fn_alojamiento;
/


-- ==============================================================
-- FUNCION FN_DESCUENTO_CONSUMOS
--
-- Determina el descuento aplicable al monto de consumos
-- segun la tabla TRAMOS_CONSUMOS y retorna el monto
-- del descuento calculado (no el porcentaje).
-- ==============================================================

CREATE OR REPLACE FUNCTION fn_descuento_consumos(p_monto IN NUMBER)
RETURN NUMBER IS
    v_pct NUMBER := 0;
BEGIN
    SELECT NVL(pct, 0) INTO v_pct
    FROM   tramos_consumos
    WHERE  p_monto BETWEEN vmin_tramo AND vmax_tramo;
    RETURN ROUND(p_monto * v_pct);
EXCEPTION WHEN OTHERS THEN RETURN 0;
END fn_descuento_consumos;
/


-- ==============================================================
-- PROCEDIMIENTO PRC_CALCULO_PAGOS
--
-- Proceso principal de cobranza. Calcula y almacena el detalle
-- de pago de todos los huespedes con salida en p_fecha.
--
-- Reglas de negocio aplicadas:
--   Alojamiento  = SUM((hab + minibar) * estadia)       [USD]
--   Consumos     = desde TOTAL_CONSUMOS                 [USD]
--   Tours        = SUM(valor_tour * num_personas)       [USD]
--   Personas     = ROUND(35000 / tipo_cambio)           [USD]
--   Subtotal     = alojamiento + consumos + tours + personas
--   Desc.consumo = segun tramo en TRAMOS_CONSUMOS
--   Desc.agencia = 12% del subtotal, solo VIAJES ALBERTI
--   Total        = subtotal - desc.consumo - desc.agencia
--   Almacenado   = todos los valores * tipo_cambio      [CLP]
--
-- NOTA: las tablas de salida se limpian ANTES de llamar a este
-- procedimiento (ver bloque de ejecucion al final del script).
-- No hacerlo aqui evita ORA-12838 y deadlocks con las
-- transacciones autonomas de FN_AGENCIA y FN_CONSUMOS.
-- ==============================================================

CREATE OR REPLACE PROCEDURE prc_calculo_pagos(
    p_fecha IN DATE   DEFAULT TO_DATE('18/08/2021','DD/MM/YYYY'),
    p_tc    IN NUMBER DEFAULT 915  -- tipo de cambio peso/dolar
) IS
    v_ag    VARCHAR2(40);
    v_al    NUMBER;  v_co   NUMBER;  v_to   NUMBER;  v_pe  NUMBER;
    v_sub   NUMBER;  v_dc   NUMBER;  v_da   NUMBER;  v_tot NUMBER;
    v_al_p  NUMBER;  v_co_p NUMBER;  v_to_p NUMBER;
    v_sub_p NUMBER;  v_dc_p NUMBER;  v_da_p NUMBER;  v_tot_p NUMBER;

    -- Cursor: huespedes cuya fecha de salida (ingreso + estadia) es p_fecha
    CURSOR c IS
        SELECT DISTINCT h.id_huesped,
               h.appat_huesped||' '||h.apmat_huesped||' '||h.nom_huesped AS nombre
        FROM   huesped h JOIN reserva r ON h.id_huesped = r.id_huesped
        WHERE  (r.ingreso + r.estadia) = p_fecha
        ORDER  BY h.id_huesped;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Inicio: '||TO_CHAR(p_fecha,'DD/MM/YYYY')||' TC:$'||p_tc);

    FOR rec IN c LOOP
        -- Obtener agencia (registra en REG_ERRORES si no existe)
        v_ag  := fn_agencia(rec.id_huesped);
        -- Calcular alojamiento en USD (parametrico, sin fecha fija)
        v_al  := fn_alojamiento(rec.id_huesped, p_fecha);
        -- Obtener consumos en USD desde TOTAL_CONSUMOS
        v_co  := fn_consumos(rec.id_huesped);
        -- Obtener tours en USD desde el package; guardar tambien en variable global
        pkg_hotel.g_monto_tours := pkg_hotel.fn_monto_tours(rec.id_huesped);
        v_to  := pkg_hotel.g_monto_tours;
        -- Cargo por personas: $35.000 CLP por persona convertido a USD
        v_pe  := ROUND(35000 / p_tc);

        -- Calculos de subtotal, descuentos y total en USD
        v_sub := v_al + v_co + v_to + v_pe;
        v_dc  := fn_descuento_consumos(v_co);
        IF v_ag = 'VIAJES ALBERTI' THEN
            v_da := ROUND(v_sub * 0.12);  -- 12% descuento solo para Viajes Alberti
        ELSE
            v_da := 0;
        END IF;
        v_tot := v_sub - v_dc - v_da;

        -- Conversion a pesos chilenos (redondeado a enteros)
        v_al_p  := ROUND(v_al  * p_tc);
        v_co_p  := ROUND(v_co  * p_tc);
        v_to_p  := ROUND(v_to  * p_tc);
        v_sub_p := ROUND(v_sub * p_tc);
        v_dc_p  := ROUND(v_dc  * p_tc);
        v_da_p  := ROUND(v_da  * p_tc);
        v_tot_p := ROUND(v_tot * p_tc);

        -- Insertar resultado en DETALLE_DIARIO_HUESPEDES
        INSERT INTO detalle_diario_huespedes (
            id_huesped, nombre, agencia,
            alojamiento, consumos, tours,
            subtotal_pago, descuento_consumos, descuentos_agencia, total
        ) VALUES (
            rec.id_huesped, rec.nombre, v_ag,
            v_al_p, v_co_p, v_to_p,
            v_sub_p, v_dc_p, v_da_p, v_tot_p
        );
        -- COMMIT por registro: libera el lock sobre DETALLE_DIARIO_HUESPEDES
        -- antes de la siguiente iteracion, evitando ORA-12838.
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('OK '||rec.id_huesped||' '||v_ag||' $'||v_tot_p);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Fin del proceso.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: '||SQLERRM);
        RAISE;
END prc_calculo_pagos;
/


-- ==============================================================
-- EJECUCION DEL PROCESO
--
-- Paso 1: limpiar tablas en transaccion separada con COMMIT.
--   Hacerlo aqui y no dentro del procedimiento evita que la
--   transaccion principal mantenga locks sobre REG_ERRORES y
--   DETALLE_DIARIO_HUESPEDES mientras corren las funciones
--   autonomas, lo que causaria ORA-12838 y ORA-00060.
--
-- Paso 2: ejecutar el proceso con fecha 18/08/2021 y TC $915.
-- ==============================================================

BEGIN
    DELETE FROM reg_errores;
    DELETE FROM detalle_diario_huespedes;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Tablas limpiadas.');
END;
/

BEGIN
    prc_calculo_pagos(
        p_fecha => TO_DATE('18/08/2021','DD/MM/YYYY'),
        p_tc    => 915
    );
END;
/

-- Resultado del proceso de cobranza
SELECT * FROM detalle_diario_huespedes ORDER BY id_huesped;

-- Errores registrados durante el proceso
SELECT * FROM reg_errores ORDER BY id_error;