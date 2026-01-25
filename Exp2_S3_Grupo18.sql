
-- ------------------------------------------------------------
--  CASO 1: GENERACIÓN DE REPORTE DE MOROSIDAD EN PAGOS
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- VARIABLE BIND: Año de acreditación
-- ------------------------------------------------------------
VARIABLE b_anio_acreditacion NUMBER;
EXEC :b_anio_acreditacion := EXTRACT(YEAR FROM SYSDATE);

-- ------------------------------------------------------------
-- BLOQUE PL/SQL ANÓNIMO
-- ------------------------------------------------------------
DECLARE
    /* --------------------------------------------------------
       CURSOR EXPLÍCITO
       -------------------------------------------------------- */
    CURSOR c_morosidad IS
        SELECT
            pac.pac_run,
            pac.dv_run,
            pac.pnombre,
            pac.snombre,
            pac.apaterno,
            pac.amaterno,
            pa.ate_id,
            pa.fecha_venc_pago,
            pa.fecha_pago,
            esp.nombre AS nombre_especialidad,
            TRUNC(pa.fecha_pago - pa.fecha_venc_pago) AS dias_morosidad,
            pac.fecha_nacimiento
        FROM 
            PAGO_ATENCION pa
            INNER JOIN ATENCION ate ON pa.ate_id = ate.ate_id
            INNER JOIN PACIENTE pac ON ate.pac_run = pac.pac_run
            INNER JOIN ESPECIALIDAD esp ON ate.esp_id = esp.esp_id
        WHERE 
            pa.fecha_pago > pa.fecha_venc_pago
            AND EXTRACT(YEAR FROM pa.fecha_venc_pago) = :b_anio_acreditacion - 1
        ORDER BY 
            pa.fecha_venc_pago, pac.apaterno;

    /* ------------------------------------------------------------
       REGISTRO PL/SQL
       ------------------------------------------------------------ */
    r_morosidad c_morosidad%ROWTYPE;

    /* ------------------------------------------------------------
       VARRAY: Multas por día según especialidad
       ------------------------------------------------------------ */
    TYPE t_multas IS VARRAY(7) OF NUMBER;
    v_multas t_multas := t_multas(
        1200, -- 1: Cirugía General / Dermatología
        1300, -- 2: Ortopedia / Traumatología
        1700, -- 3: Inmunología / Otorrinolaringología
        1900, -- 4: Fisiatría / Medicina Interna
        1100, -- 5: Medicina General
        2000, -- 6: Psiquiatría Adultos
        2300  -- 7: Cirugía Digestiva / Reumatología
    );

    /* ------------------------------------------------------------
       VARIABLES DE CÁLCULO
       ------------------------------------------------------------ */
    v_multa_dia         NUMBER;      -- Multa por día de atraso
    v_descuento         NUMBER := 0; -- Porcentaje de descuento
    v_monto_multa       NUMBER;      -- Monto final de la multa
    v_edad              NUMBER;      -- Edad del paciente
    v_nombre_completo   VARCHAR2(100); -- Nombre completo del paciente

BEGIN
    /* ------------------------------------------------------------
       LIMPIEZA DE TABLA RESULTADO
       Permite ejecutar el bloque múltiples veces
       ------------------------------------------------------------ */
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
    
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO DE GENERACIÓN DE REPORTE DE MOROSIDAD');
    DBMS_OUTPUT.PUT_LINE('Año de acreditación: ' || :b_anio_acreditacion);
    DBMS_OUTPUT.PUT_LINE('Procesando datos del año: ' || (:b_anio_acreditacion - 1));
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('');

    /* ------------------------------------------------------------
       PROCESAMIENTO DE ATENCIONES MOROSAS
       ------------------------------------------------------------ */
    OPEN c_morosidad;
    LOOP
        FETCH c_morosidad INTO r_morosidad;
        EXIT WHEN c_morosidad%NOTFOUND;

        /* ------------------------------------------------------------
           CÁLCULO DE EDAD DEL PACIENTE
           Usa MONTHS_BETWEEN para obtener la edad exacta
           ------------------------------------------------------------ */
        v_edad := TRUNC(MONTHS_BETWEEN(SYSDATE, r_morosidad.fecha_nacimiento) / 12);

        /* ------------------------------------------------------------
           DETERMINACIÓN DE MULTA POR DÍA SEGÚN ESPECIALIDAD
           ------------------------------------------------------------ */
        CASE 
            WHEN r_morosidad.nombre_especialidad = 'Medicina General' THEN
                v_multa_dia := v_multas(5);
            
            WHEN r_morosidad.nombre_especialidad = 'Psiquiatría Adultos' THEN
                v_multa_dia := v_multas(6);
            
            WHEN r_morosidad.nombre_especialidad IN ('Ortopedia y Traumatología') THEN
                v_multa_dia := v_multas(2);
            
            WHEN r_morosidad.nombre_especialidad IN ('Inmunología', 'Otorrinolaringología') THEN
                v_multa_dia := v_multas(3);
            
            WHEN r_morosidad.nombre_especialidad IN ('Fisiatría', 'Medicina Interna') THEN
                v_multa_dia := v_multas(4);
            
            WHEN r_morosidad.nombre_especialidad IN ('Cirugía Digestiva', 'Reumatología') THEN
                v_multa_dia := v_multas(7);
            
            ELSE
                v_multa_dia := v_multas(1);
        END CASE;

        /* ------------------------------------------------------------
           CÁLCULO DE DESCUENTO POR TERCERA EDAD
           Si el paciente tiene 60 años o más, aplica descuento
           ------------------------------------------------------------ */
        IF v_edad >= 60 THEN
            BEGIN
                SELECT porcentaje_descto
                INTO v_descuento
                FROM PORC_DESCTO_3RA_EDAD
                WHERE v_edad BETWEEN anno_ini AND anno_ter;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_descuento := 0;
            END;
        ELSE
            v_descuento := 0;
        END IF;

        /* ------------------------------------------------------------
           CÁLCULO DEL MONTO FINAL DE LA MULTA
           Fórmula: (días * multa_día) - descuento
           ------------------------------------------------------------ */
        v_monto_multa := (r_morosidad.dias_morosidad * v_multa_dia) - 
                         ((r_morosidad.dias_morosidad * v_multa_dia) * v_descuento / 100);

        /* ------------------------------------------------------------
           CONSTRUCCIÓN DEL NOMBRE COMPLETO
           Formato: Primer nombre + Apellido paterno
           ------------------------------------------------------------ */
        v_nombre_completo := r_morosidad.pnombre || ' ' || r_morosidad.snombre || ' ' || r_morosidad.apaterno || ' ' || r_morosidad.amaterno;

        /* ------------------------------------------------------------
           INSERCIÓN EN TABLA PAGO_MOROSO
           ------------------------------------------------------------ */
        INSERT INTO PAGO_MOROSO (
            pac_run,
            pac_dv_run,
            pac_nombre,
            ate_id,
            fecha_venc_pago,
            fecha_pago,
            dias_morosidad,
            especialidad_atencion,
            monto_multa
        ) VALUES (
            r_morosidad.pac_run,
            r_morosidad.dv_run,
            v_nombre_completo,
            r_morosidad.ate_id,
            r_morosidad.fecha_venc_pago,
            r_morosidad.fecha_pago,
            r_morosidad.dias_morosidad,
            r_morosidad.nombre_especialidad,
            v_monto_multa
        );

    END LOOP;
    CLOSE c_morosidad;

    /* ------------------------------------------------------------
       CONFIRMACIÓN DE TRANSACCIÓN
       ------------------------------------------------------------ */
    COMMIT;

    /* ------------------------------------------------------------
       MENSAJE DE FINALIZACIÓN
       ------------------------------------------------------------ */
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO COMPLETADO EXITOSAMENTE');
    DBMS_OUTPUT.PUT_LINE('Total de registros procesados: ' || SQL%ROWCOUNT);
    DBMS_OUTPUT.PUT_LINE('==========================================================');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        RAISE;
END;
/

-- ------------------------------------------------------------
-- CONSULTA DE VERIFICACIÓN
-- Muestra los resultados almacenados en PAGO_MOROSO
-- ------------------------------------------------------------
SELECT 
    pac_run,
    pac_dv_run,
    pac_nombre,
    ate_id,
    TO_CHAR(fecha_venc_pago, 'DD/MM/YYYY') AS fecha_vencimiento,
    TO_CHAR(fecha_pago, 'DD/MM/YYYY') AS fecha_pago,
    dias_morosidad,
    especialidad_atencion,
    monto_multa
FROM 
    PAGO_MOROSO
ORDER BY 
    fecha_venc_pago, pac_nombre;



-- ------------------------------------------------------------
-- CASO 2: ASIGNACIÓN DE MÉDICOS A SERVICIO COMUNITARIO
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- PREPARACIÓN: Eliminar y recrear tabla resultado
-- ------------------------------------------------------------
DROP TABLE MEDICO_SERVICIO_COMUNIDAD;

CREATE TABLE MEDICO_SERVICIO_COMUNIDAD(
    id_med_scomun NUMBER(2) GENERATED ALWAYS AS IDENTITY MINVALUE 1 
    MAXVALUE 9999999999999999999999999999
    INCREMENT BY 1 START WITH 1
    CONSTRAINT PK_MED_SERV_COMUNIDAD PRIMARY KEY,
    unidad VARCHAR2(50) NOT NULL,
    run_medico VARCHAR2(15) NOT NULL,
    nombre_medico VARCHAR2(50) NOT NULL,
    correo_institucional VARCHAR2(25) NOT NULL,
    total_aten_medicas NUMBER(2) NOT NULL,
    destinacion VARCHAR2(50) NOT NULL
);

-- ------------------------------------------------------------
-- BLOQUE PL/SQL ANÓNIMO
-- ------------------------------------------------------------
DECLARE
    /* ------------------------------------------------------------
       CURSOR EXPLÍCITO
       ------------------------------------------------------------ */
    CURSOR c_medicos IS
        SELECT 
            m.med_run,
            m.dv_run,
            m.pnombre,
            m.snombre,
            m.apaterno,
            m.amaterno,
            u.uni_id,
            u.nombre AS nombre_unidad,
            COUNT(a.ate_id) AS total_atenciones
        FROM 
            MEDICO m
            INNER JOIN UNIDAD u ON m.uni_id = u.uni_id
            LEFT JOIN ATENCION a ON m.med_run = a.med_run 
                AND EXTRACT(YEAR FROM a.fecha_atencion) = EXTRACT(YEAR FROM SYSDATE) - 1
        GROUP BY 
            m.med_run, m.dv_run, m.pnombre, m.snombre, 
            m.apaterno, m.amaterno, u.uni_id, u.nombre
        ORDER BY 
            u.nombre, m.apaterno;

    /* ------------------------------------------------------------
       REGISTRO PL/SQL
       ------------------------------------------------------------ */
    r_medico c_medicos%ROWTYPE;

    /* ------------------------------------------------------------
       VARRAY: Destinaciones posibles
       Índice 1: SAPU
       Índice 2: Hospitales Públicos
       Índice 3: CESFAM
       ------------------------------------------------------------ */
    TYPE t_destinaciones IS VARRAY(3) OF VARCHAR2(60);
    v_destinaciones t_destinaciones := t_destinaciones(
        'Servicio de Atención Primaria de Urgencia (SAPU)',
        'Hospitales del área de la Salud Pública',
        'Centros de Salud Familiar (CESFAM)'
    );

    /* ------------------------------------------------------------
       VARIABLES DE PROCESO
       ------------------------------------------------------------ */
    v_max_atenciones    NUMBER;          -- Máximo de atenciones del año
    v_destinacion       VARCHAR2(60);    -- Destinación asignada
    v_correo            VARCHAR2(25);    -- Correo institucional
    v_run_completo      VARCHAR2(15);    -- RUN con DV
    v_nombre_completo   VARCHAR2(50);    -- Nombre completo del médico
    v_sigla_unidad      VARCHAR2(2);     -- Sigla de la unidad
    v_antepenultima     VARCHAR2(1);     -- Antepenúltima letra apellido
    v_penultima         VARCHAR2(1);     -- Penúltima letra apellido
    v_tres_ultimos      VARCHAR2(3);     -- Tres últimos dígitos RUN
    v_contador          NUMBER := 0;     -- Contador de registros

BEGIN
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO DE ASIGNACIÓN A SERVICIO COMUNITARIO');
    DBMS_OUTPUT.PUT_LINE('Año de proceso: ' || (EXTRACT(YEAR FROM SYSDATE) - 1));
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('');

    /* ------------------------------------------------------------
       OBTENCIÓN DEL MÁXIMO DE ATENCIONES DEL AÑO ANTERIOR
       ------------------------------------------------------------ */
    SELECT MAX(total_atenciones)
    INTO v_max_atenciones
    FROM (
        SELECT COUNT(*) AS total_atenciones
        FROM ATENCION
        WHERE EXTRACT(YEAR FROM fecha_atencion) = EXTRACT(YEAR FROM SYSDATE) - 1
        GROUP BY med_run
    );

    DBMS_OUTPUT.PUT_LINE('Máximo de atenciones en el año: ' || v_max_atenciones);
    DBMS_OUTPUT.PUT_LINE('');

    /* ------------------------------------------------------------
       PROCESAMIENTO DE MÉDICOS
       ------------------------------------------------------------ */
    OPEN c_medicos;
    LOOP
        FETCH c_medicos INTO r_medico;
        EXIT WHEN c_medicos%NOTFOUND;

        /* ------------------------------------------------------------
           FILTRO: Solo procesar médicos con menos del máximo
           ------------------------------------------------------------ */
        IF r_medico.total_atenciones < v_max_atenciones THEN

            /* ------------------------------------------------------------
               DETERMINACIÓN DE DESTINACIÓN SEGÚN UNIDAD
               Y TOTAL DE ATENCIONES
               ------------------------------------------------------------ */
            CASE 
                -- Atención Adulto y Atención Ambulatoria -> SAPU
                WHEN r_medico.nombre_unidad IN ('ATENCIÓN ADULTO', 'ATENCIÓN AMBULATORIA') THEN
                    v_destinacion := v_destinaciones(1); 

                -- Atención Urgencia
                WHEN r_medico.nombre_unidad = 'ATENCIÓN URGENCIA' THEN
                    IF r_medico.total_atenciones BETWEEN 0 AND 3 THEN
                        v_destinacion := v_destinaciones(1);
                    ELSE
                        v_destinacion := v_destinaciones(2);
                    END IF;

                -- Cardiología y Oncológica -> Hospitales
                WHEN r_medico.nombre_unidad IN ('CARDIOLOGÍA', 'ONCOLÓGICA') THEN
                    v_destinacion := v_destinaciones(2);

                -- Cirugía y Cirugía Plástica
                WHEN r_medico.nombre_unidad IN ('CIRUGÍA', 'CIRUGÍA PLÁSTICA') THEN
                    IF r_medico.total_atenciones BETWEEN 0 AND 3 THEN
                        v_destinacion := v_destinaciones(1);
                    ELSE
                        v_destinacion := v_destinaciones(2); 
                    END IF;

                -- Paciente Crítico -> Hospitales
                WHEN r_medico.nombre_unidad = 'PACIENTE CRÍTICO' THEN
                    v_destinacion := v_destinaciones(2);

                -- Psiquiatría y Salud Mental -> CESFAM
                WHEN r_medico.nombre_unidad = 'PSIQUIATRÍA Y SALUD MENTAL' THEN
                    v_destinacion := v_destinaciones(3);

                -- Traumatología Adulto
                WHEN r_medico.nombre_unidad = 'TRAUMATOLOGÍA ADULTO' THEN
                    IF r_medico.total_atenciones BETWEEN 0 AND 3 THEN
                        v_destinacion := v_destinaciones(1);
                    ELSE
                        v_destinacion := v_destinaciones(2); 
                    END IF;

                -- Por defecto: SAPU
                ELSE
                    v_destinacion := v_destinaciones(1);
            END CASE;

            /* ------------------------------------------------------------
               CONSTRUCCIÓN DEL CORREO INSTITUCIONAL
               Formato: sigla_unidad(2) + antepenúltima(1) + 
                       penúltima(1) + tres_últimos_run(3) + @ketekura.cl
               ------------------------------------------------------------ */
            
            -- Obtener sigla de unidad (primeras 2 letras)
            v_sigla_unidad := UPPER(SUBSTR(r_medico.nombre_unidad, 1, 2));

            -- Obtener antepenúltima letra del apellido paterno
            IF LENGTH(r_medico.apaterno) >= 3 THEN
                v_antepenultima := LOWER(SUBSTR(r_medico.apaterno, -3, 1));
            ELSE
                v_antepenultima := LOWER(SUBSTR(r_medico.apaterno, 1, 1));
            END IF;

            -- Obtener penúltima letra del apellido paterno
            IF LENGTH(r_medico.apaterno) >= 2 THEN
                v_penultima := LOWER(SUBSTR(r_medico.apaterno, -2, 1));
            ELSE
                v_penultima := LOWER(SUBSTR(r_medico.apaterno, -1, 1));
            END IF;

            -- Obtener tres últimos dígitos del RUN
            v_tres_ultimos := SUBSTR(LPAD(r_medico.med_run, 8, '0'), -3);

            -- Construir correo completo
            v_correo := v_sigla_unidad || v_antepenultima || v_penultima || 
                       v_tres_ultimos || '@ketekura.cl';

            /* ------------------------------------------------------------
               CONSTRUCCIÓN DE DATOS COMPLEMENTARIOS
               ------------------------------------------------------------ */
             v_run_completo := TO_CHAR(r_medico.med_run, 'FM99G999G999', 'NLS_NUMERIC_CHARACTERS='',.''') || 
                             '-' || r_medico.dv_run;
                             
            v_nombre_completo := r_medico.pnombre || ' ' || 
                                r_medico.snombre || ' ' || 
                                r_medico.apaterno || ' ' || 
                                r_medico.amaterno;

            /* ------------------------------------------------------------
               INSERCIÓN EN TABLA MEDICO_SERVICIO_COMUNIDAD
               ------------------------------------------------------------ */
            INSERT INTO MEDICO_SERVICIO_COMUNIDAD (
                unidad,
                run_medico,
                nombre_medico,
                correo_institucional,
                total_aten_medicas,
                destinacion
            ) VALUES (
                r_medico.nombre_unidad,
                v_run_completo,
                v_nombre_completo,
                v_correo,
                r_medico.total_atenciones,
                v_destinacion
            );

            v_contador := v_contador + 1;

        END IF;

    END LOOP;
    CLOSE c_medicos;

    /* ------------------------------------------------------------
       CONFIRMACIÓN DE TRANSACCIÓN
       ------------------------------------------------------------ */
    COMMIT;

    /* ------------------------------------------------------------
       MENSAJE DE FINALIZACIÓN
       ------------------------------------------------------------ */
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO COMPLETADO EXITOSAMENTE');
    DBMS_OUTPUT.PUT_LINE('Total de médicos asignados: ' || v_contador);
    DBMS_OUTPUT.PUT_LINE('==========================================================');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        RAISE;
END;
/

-- ------------------------------------------------------------
-- CONSULTA DE VERIFICACIÓN
-- ------------------------------------------------------------
    SELECT 
        id_med_scomun,
        unidad,
        run_medico,
        nombre_medico,
        correo_institucional,
        total_aten_medicas,
        destinacion
    FROM 
        MEDICO_SERVICIO_COMUNIDAD

