
----------------------------------------------------------------
-- ::::::::::::::::::::::::: CASO ::::::::::::::::::::::::::::::
----------------------------------------------------------------

/* Configuración de seguridad para fechas */
ALTER SESSION SET NLS_DATE_FORMAT = 'DD/MM/YYYY';

VAR v_fecha_proceso VARCHAR2(20);
EXEC :v_fecha_proceso := TO_CHAR(SYSDATE, 'DD/MM/YYYY');

DECLARE
    -- ========================================================================
    -- DECLARACIÓN DE VARIABLES
    -- ========================================================================
    
    -- Variables para información del empleado (usando %TYPE para eficiencia)
    v_numrun_emp        EMPLEADO.NUMRUN_EMP%TYPE;
    v_dvrun_emp         EMPLEADO.DVRUN_EMP%TYPE;
    v_pnombre_emp       EMPLEADO.PNOMBRE_EMP%TYPE;
    v_snombre_emp       EMPLEADO.SNOMBRE_EMP%TYPE;
    v_appaterno_emp     EMPLEADO.APPATERNO_EMP%TYPE;
    v_apmaterno_emp     EMPLEADO.APMATERNO_EMP%TYPE;
    v_sueldo_base       EMPLEADO.SUELDO_BASE%TYPE;
    v_fecha_nac         EMPLEADO.FECHA_NAC%TYPE;
    v_fecha_contrato    EMPLEADO.FECHA_CONTRATO%TYPE;
    v_id_estado_civil   EMPLEADO.ID_ESTADO_CIVIL%TYPE;
    
    -- Variables calculadas para nombre de usuario
    v_letra_estado_civil    VARCHAR2(1);
    v_tres_letras_nombre    VARCHAR2(3);
    v_largo_nombre          NUMBER(2);
    v_ultimo_digito_sueldo  VARCHAR2(1);
    v_annos_trabajando      NUMBER(2);
    v_x_adicional           VARCHAR2(1);
    
    -- Variables calculadas para clave
    v_tercer_digito_run     VARCHAR2(1);
    v_anno_nac_mas_dos      VARCHAR2(4);
    v_tres_ultimos_sueldo   VARCHAR2(3);
    v_dos_letras_apellido   VARCHAR2(2);
    v_mes_anno_bd           VARCHAR2(6);
    
    -- Variables finales
    v_nombre_usuario        VARCHAR2(20);
    v_clave_usuario         VARCHAR2(20);
    v_nombre_completo       VARCHAR2(90);
    
    -- Contador de iteraciones para validar proceso completo
    v_contador_empleados    NUMBER := 0;
    v_total_empleados       NUMBER := 0;
    
BEGIN
    -- ========================================================================
    -- TRUNCAR TABLA USUARIO_CLAVE
    -- ========================================================================
    -- Se utiliza SQL dinámico para truncar la tabla y permitir ejecuciones
    -- múltiples del bloque PL/SQL
    EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';
    
    -- ========================================================================
    -- CONTAR TOTAL DE EMPLEADOS PARA VALIDACIÓN POSTERIOR
    -- ========================================================================
    -- Se obtiene el total de empleados entre ID 100 y 320
    SELECT COUNT(*) 
    INTO v_total_empleados
    FROM EMPLEADO
    WHERE id_emp BETWEEN 100 AND 320;
    
    -- ========================================================================
    -- PROCESAMIENTO DE TODOS LOS EMPLEADOS
    -- ========================================================================
    -- Se procesan empleados desde ID 100 hasta 320 incrementando de 10 en 10
    FOR v_id_emp IN 100..320 LOOP
        
        IF MOD(v_id_emp, 10) = 0 THEN
            
            BEGIN
                -- ============================================================
                -- CONSULTA DE DATOS DEL EMPLEADO
                -- ============================================================
                -- Se obtienen todos los datos necesarios del empleado actual
                SELECT 
                    numrun_emp,
                    dvrun_emp,
                    pnombre_emp,
                    snombre_emp,
                    appaterno_emp,
                    apmaterno_emp,
                    sueldo_base,
                    fecha_nac,
                    fecha_contrato,
                    id_estado_civil
                INTO 
                    v_numrun_emp,
                    v_dvrun_emp,
                    v_pnombre_emp,
                    v_snombre_emp,
                    v_appaterno_emp,
                    v_apmaterno_emp,
                    v_sueldo_base,
                    v_fecha_nac,
                    v_fecha_contrato,
                    v_id_estado_civil
                FROM EMPLEADO
                WHERE id_emp = v_id_emp;
                
                -- Incrementar contador de empleados procesados
                v_contador_empleados := v_contador_empleados + 1;
                
                -- ============================================================
                -- GENERACIÓN DEL NOMBRE DE USUARIO
                -- ============================================================
                
                -- a) Primera letra del estado civil en minúscula
                v_letra_estado_civil := CASE v_id_estado_civil
                    WHEN 10 THEN 'c'  -- Casado
                    WHEN 20 THEN 'd'  -- Divorciado
                    WHEN 30 THEN 's'  -- Soltero
                    WHEN 40 THEN 'v'  -- Viudo
                    WHEN 50 THEN 'p'  -- Separado
                    WHEN 60 THEN 'a'  -- Acuerdo de unión civil
                    ELSE 'x'
                END;
                
                -- b) Tres primeras letras del primer nombre
                v_tres_letras_nombre := UPPER(SUBSTR(v_pnombre_emp, 1, 3));
                
                -- c) Largo del primer nombre
                v_largo_nombre := LENGTH(v_pnombre_emp);
                
                -- e) Ultimo dígito del sueldo base
                v_ultimo_digito_sueldo := SUBSTR(TO_CHAR(v_sueldo_base), -1, 1);
                
                -- g) Años trabajando en la empresa
                v_annos_trabajando := EXTRACT(YEAR FROM TO_DATE(:v_fecha_proceso, 'DD/MM/YYYY')) - 
                                        EXTRACT(YEAR FROM v_fecha_contrato);
                                
                -- h) Si lleva menos de 10 años, agregar X
                IF v_annos_trabajando < 10 THEN
                    v_x_adicional := 'X';
                ELSE
                    v_x_adicional := '';
                END IF;
                
                -- Concatenar nombre de usuario
                v_nombre_usuario := v_letra_estado_civil || 
                                   v_tres_letras_nombre || 
                                   v_largo_nombre || 
                                   '*' || 
                                   v_ultimo_digito_sueldo || 
                                   v_dvrun_emp || 
                                   v_annos_trabajando || 
                                   v_x_adicional;
                
                -- ============================================================
                -- GENERACIÓN DE LA CLAVE
                -- ============================================================
                
                -- a) Tercer dígito del run
                v_tercer_digito_run := SUBSTR(TO_CHAR(v_numrun_emp), 3, 1);
                
                -- b) Año de nacimiento aumentado en dos
                v_anno_nac_mas_dos := TO_CHAR(EXTRACT(YEAR FROM v_fecha_nac) + 2);
                
                -- c) Tres últimos dígitos del sueldo disminuido en uno
                v_tres_ultimos_sueldo := SUBSTR(TO_CHAR(v_sueldo_base - 1), -3, 3);
                
                -- d) Dos letras del apellido según estado civil
                v_dos_letras_apellido := CASE v_id_estado_civil
                    WHEN 10 THEN LOWER(SUBSTR(v_appaterno_emp, 1, 2))  -- Casado: dos primeras
                    WHEN 20 THEN LOWER(SUBSTR(v_appaterno_emp, 1, 1) || SUBSTR(v_appaterno_emp, -1, 1))  -- Divorciado: primera y última
                    WHEN 30 THEN LOWER(SUBSTR(v_appaterno_emp, 1, 1) || SUBSTR(v_appaterno_emp, -1, 1))  -- Soltero: primera y última
                    WHEN 40 THEN LOWER(SUBSTR(v_appaterno_emp, -3, 2))  -- Viudo: antepenúltima y penúltima
                    WHEN 50 THEN LOWER(SUBSTR(v_appaterno_emp, -2, 2))  -- Separado: dos últimas
                    WHEN 60 THEN LOWER(SUBSTR(v_appaterno_emp, 1, 2))  -- Acuerdo unión civil: dos primeras
                    ELSE 'xx'
                END;
                
                -- f) Mes y año de la base de datos
                v_mes_anno_bd := TO_CHAR(TO_DATE(:v_fecha_proceso, 'DD/MM/YYYY'), 'MMYYYY');
                
                -- Concatenar clave
                v_clave_usuario := v_tercer_digito_run || 
                                  v_anno_nac_mas_dos || 
                                  v_tres_ultimos_sueldo || 
                                  v_dos_letras_apellido || 
                                  v_id_emp || 
                                  v_mes_anno_bd;
                
                -- ============================================================
                -- NOMBRE COMPLETO DEL EMPLEADO
                -- ============================================================
                -- Se construye el nombre completo concatenando nombres y apellidos
                v_nombre_completo := v_pnombre_emp || ' ' || v_snombre_emp  || ' ' || v_appaterno_emp  || ' ' || v_apmaterno_emp;
                
                -- ============================================================
                -- INSERCIÓN EN TABLA USUARIO_CLAVE
                -- ============================================================
                -- Se almacena la información generada en la tabla destino
                INSERT INTO USUARIO_CLAVE (
                    id_emp,
                    numrun_emp,
                    dvrun_emp,
                    nombre_empleado,
                    nombre_usuario,
                    clave_usuario
                ) VALUES (
                    v_id_emp,
                    v_numrun_emp,
                    v_dvrun_emp,
                    v_nombre_completo,
                    v_nombre_usuario,
                    v_clave_usuario
                );
                
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Si no existe empleado con ese ID, continuar con el siguiente
                    NULL;
                WHEN OTHERS THEN
                    -- Mostrar error y continuar
                    DBMS_OUTPUT.PUT_LINE('Error procesando empleado ' || v_id_emp || ': ' || SQLERRM);
            END;
            
        END IF;
        
    END LOOP;
    
    -- ========================================================================
    -- VALIDACIÓN Y CONFIRMACIÓN DE TRANSACCIONES
    -- ========================================================================
    -- Solo se confirma si se procesaron todos los empleados correctamente
    IF v_contador_empleados = v_total_empleados THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('========================================');
        DBMS_OUTPUT.PUT_LINE('Proceso completado exitosamente');
        DBMS_OUTPUT.PUT_LINE('Total empleados procesados: ' || v_contador_empleados);
        DBMS_OUTPUT.PUT_LINE('TransacciÃ³n confirmada (COMMIT)');
        DBMS_OUTPUT.PUT_LINE('========================================');
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('========================================');
        DBMS_OUTPUT.PUT_LINE('ERROR: No se procesaron todos los empleados');
        DBMS_OUTPUT.PUT_LINE('Esperados: ' || v_total_empleados);
        DBMS_OUTPUT.PUT_LINE('Procesados: ' || v_contador_empleados);
        DBMS_OUTPUT.PUT_LINE('TransacciÃ³n revertida (ROLLBACK)');
        DBMS_OUTPUT.PUT_LINE('========================================');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('========================================');
        DBMS_OUTPUT.PUT_LINE('ERROR CRÃ?TICO: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('TransacciÃ³n revertida (ROLLBACK)');
        DBMS_OUTPUT.PUT_LINE('========================================');
END;
/

-- ============================================================================
-- CONSULTA DE VERIFICACIÓN
-- ============================================================================
-- Se muestran los resultados ordenados por ID de empleado
SELECT 
    id_emp AS "ID EMPLEADO",
    numrun_emp || '-' || dvrun_emp AS "RUN",
    nombre_empleado AS "NOMBRE COMPLETO",
    nombre_usuario AS "NOMBRE USUARIO",
    clave_usuario AS "CLAVE USUARIO"
FROM USUARIO_CLAVE
ORDER BY id_emp;