(import sqlite3)
(import ./helper :as helper)
(import ./db/sql :as sql)


(defmacro with-db-connection
  `A macro that takes a binding array, ex: [conn "x.sqlite3"] and expressions and executes them in the context of the connection.

   Example:

   (import sqlite3)
   (import ./db)

   (db/with-db-connection [conn "dev.sqlite3"]
     (sqlite3/eval conn "select 1;" {}))`
  [binding & body]
  ~(with [,(first binding) (,sqlite3/open ,(get binding 1)) ,sqlite3/close]
    ,;body))


(defn kebab-case-keys [dict]
  (->> (helper/map-keys helper/kebab-case dict)
       (helper/map-keys keyword)))


(defn snake-case-keys [dict]
  (->> (helper/map-keys helper/snake-case dict)
       (helper/map-keys keyword)))


(defn query [db sql &opt params]
  (default params {})
  (let [connection (if (dictionary? db)
                     (get db :connection)
                     db)
        sql (string sql ";")
        params (if (dictionary? params)
                 (snake-case-keys params)
                 params)]
    (->> (sqlite3/eval connection sql params)
         (map kebab-case-keys))))


(defn execute [db sql &opt params]
  (default params {})
  (let [connection (if (dictionary? db)
                     (get db :connection)
                     db)
        sql (string sql ";")
        params (if (dictionary? params)
                (snake-case-keys params)
                params)]
    (sqlite3/eval connection sql params)
    (sqlite3/last-insert-rowid connection)))


(defn last-inserted [db table-name rowid]
  (let [params {:rowid rowid}
        sql (sql/from table-name {:where params :limit 1})]
    (first
      (query db sql params))))


(defn fetch [db path & args]
  (let [args (apply table args)
        sql (sql/fetch path (merge args {:limit 1}))
        params (sql/fetch-params path)]
    (-> (query db sql params)
        (get 0))))


(defn fetch-all [db path & args]
  (let [sql (sql/fetch path (apply table args))
        params (sql/fetch-params path)]
    (query db sql params)))


(defn from [db table-name & args]
  (let [opts (apply table args)
        sql (sql/from table-name opts)
        params (get opts :where {})]
    (query db sql params)))


(defn insert [db table-name params]
  (let [sql (sql/insert table-name params)]
    (->> (execute db sql params)
         (last-inserted db table-name))))


(defn insert-all [db table-name arr]
  (let [sql (sql/insert-all table-name arr)
        params (sql/insert-all-params arr)]
    (execute db sql params)
    (query db (string "select * from " (helper/snake-case table-name) " order by rowid limit " (length params)))))


(defn update [db table-name dict-or-id params]
  (let [schema (when (dictionary? db)
                 (get db :schema))
        params (if (and (dictionary? schema)
                        (= "updated_at" (get schema (helper/snake-case table-name))))
                 (merge params {:updated-at (os/time)})
                 params)
        sql (sql/update table-name params)
        id (if (dictionary? dict-or-id)
             (get dict-or-id :id)
             dict-or-id)]
    (execute db sql (merge params {:id id}))
    (fetch db [table-name id])))


(defn update-all [db table-name where-params set-params]
  (let [rows (from db table-name where-params)
        sql (sql/update-all table-name where-params set-params)
        schema (when (dictionary? db)
                 (get db :schema))
        set-params (if (and (dictionary? schema)
                            (= "updated_at" (get schema (helper/snake-case table-name))))
                     (merge set-params {:updated-at (os/time)})
                     set-params)
        params (sql/update-all-params where-params set-params)]
    (execute db sql params)
    (from db table-name (map |(table :id (get $ :id))
                          rows))))


(defn delete [db table-name dict-or-id]
  (let [id (if (dictionary? dict-or-id)
             (get dict-or-id :id)
             dict-or-id)
        row (fetch db [table-name id])
        sql (sql/delete table-name id)
        params {:id id}]
    (execute db sql params)
    row))


(defn delete-all [db table-name params &opt where-params]
  (let [rows (from db table-name params)
        params (or where-params params)
        sql (sql/delete-all table-name params)]
    (execute db sql params)
    rows))
