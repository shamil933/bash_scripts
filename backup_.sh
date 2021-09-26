#!/bin/bash
#set -x

# Скрипт бэкапит все файлы и папки указанные в переменной "$directorys_and_files".
# +Директория назначения для бэкапа указывается в переменной "$directory_destination".
# +Формирует забэкапленные файлы в тарбол с текущей датой.
# +Если тарболов скопилось больше чем указано в переменной "$TAR_COUNT", удаляет половину из них
# +а самый старый переносит в папку "$directory_archive".

# Для полного сохранения атрибутов файлов и папок при резервировании,
# +желательно запускать скрипт от администратора.
# +Запуск от пользователя также возможен, но владельцы не сохранятся.

# КОДЫ ОШИБОК:
# "164" - Ошибка свидетельствует что скрипт был завершен принудительно функцией "kill_script ()",
# +вследствии превышения допустимого времени работы заданного переменной "$ACCEPTABLE_TIME".
# +Возможно подвисла одна из утилит скрипта или произошло еще что то непредвиденное.
# +Если отладка этого не подтвердила, тогда возможно вы сильно ограничили скорость "rsync" в скрипте
# +переменной "RSYNC_SPEED" для вашего объёма файлов.
# +Также позаботьтесь чтобы время указанное вами время в переменной "$ACCEPTABLE_TIME"
# +было с запасом для корректного резервирования всех ваших файлов и архивирования предыдущего бэкапа.
# +Устраните причину ошибки, удалите руками данный файл "$LOG_WARNING" из предыдущего бэкапа,
# +и перезапустите скрипт.

# "165" - Проблема с созданием или редактированием директории назначения
# +для бэкапов("$directory_destination") в начале тела скрипта.
# +Запустите скрипт от рута, поменяйте права или укажите другую директорию

####################################################################################################
##############################       ДВЕ  УПРАВЛЯЮЩИЕ ПЕРЕМЕННЫЕ      ##############################
####################################################################################################
# ИСПОЛЬЗУЙТЕ АБСОЛЮТНЫЙ ПУТЬ В ДАННЫХ ПЕРЕМЕННЫХ!

# УКАЗАНИЕ ДИРЕКТОРИЙ И ФАЙЛОВ ДЛЯ РЕЗЕРВИРОВАНИЯ,
# Добавьте в список переменной "$directorys_and_files" директорию источник,
# +или конкретный файл согласно образцу.

declare -r directorys_and_files="
/etc/pam.d
/home/shom/scripts/attemt
/etc/apt
/home/shom/scripts/
/home/bob/hhh
/tmp
/home/shom/scripts/ssilka
"
#/home/shom
#/home/shom/.config
#/etc/network/interfaces
#/etc/group
#/etc/fstab

# УКАЗАНИE КАТАЛОГА ДЛЯ РЕЗЕРВИРОВАНИЯ.
# В данной переменной укажите директорию назначения для бэкапов.
# +Допустимо задавать директорию назначения в резервируемом каталоге.

declare -r directory_destination=/home/shom/scripts/bbb
#directory_destination="/var/log/backup_shom"

#####################################################################################################
#####      ПЕРЕМЕННЫЕ ОТВЕЧАЮЩИЕ ЗА СКОРОСТЬ КОПИРОВАНИЯ И ДОПУСТИМОЕ ВРЕМЯ РАБОТЫ СКРИПТА    #######
#####################################################################################################

# Перeменная для параметра "--bwlimit" отвечающего за скорость копирования утилитами "rsync" в скрипте.
# +Если требуется не нагружать ввод вывод накопителя, можно ограничить скорость копирования
# +несколькими мегабайтами в секунду, укажите нужные вам значения для переменной:
# +"RSYNC_SPEED=10m" = 10MBPS (мегабайт в сек), "RSYNC_SPEED=50m" = 50MBPS и т.п.
# +Значение без буквы, как например  "RSYNC_SPEED=1000" будет считаться килобайтами в секунду
# +Если указан ноль или не указано ничего, скорость будет неограниченной.
RSYNC_SPEED=100m

# Если при работе скрипта, превышено время указанное в данной переменной, то функция "kill_script ()"
# +завершит скрипт принудительно. Это на случай если подвисла одна из утилит скрипта или
# +произошло еще что то непредвиденное. Если вы ограничивайте скорость "rsync" в скрипте или
# +резервируете большие объёмы информации, позаботьтесь чтобы время указанное вами в данной переменной
# +было с запасом для корректного резервирования всех ваших файлов или увеличьте скорость копирования
# +в "RSYNC_SPEED", если вы её ограничивали.
# "ACCEPTABLE_TIME=10" - десять секунд, "ACCEPTABLE_TIME=20m" - двадцать минут и т.п.
declare -r ACCEPTABLE_TIME=10m

# Укажите в переменной максимальное количество тарболов для хранения в папке назначения,
# +При превышении параметра, половина тарболов с конца будет удаляться, самый последний пойдет в архив,
# +в папку из переменной "$directory_archive"
TAR_COUNT=20

#####################################################################################################
###############################       ОСТАЛЬНЫЕ ПЕРЕМЕННЫЕ        ###################################
#####################################################################################################

# Общий каталог для текущего бэкапа.
declare -r directory_general="$directory_destination"/backup_general_$(date +"%d.%m.%Y_%H%M")
# Подкаталог общего вышеуказанного каталога для резервируемых файлов и папок
declare -r directory_backup="$directory_general"/backup_$(date +"%d.%m.%Y")
# Подкаталог общего каталога для разыменованных ссылок
declare -r directory_backup_dereference="$directory_general"/backup_dereference_$(date +"%d.%m.%Y")
# Директория для архива
declare -r directory_archive="$directory_destination"/archive

# Файл с логом работы скрипта.
LOG="$directory_general"/LOG_$(date +"%d.%m.%Y")
# Временный файл для перенаправления ошибок через утилиту "awk" в файл "$LOG"
LOG_TMP="$directory_general"/LOG_TMP_$(date +"%d.%m.%Y")
# Файл с ошибками по некорретным завершениям скрипта.
LOG_WARNING="$directory_general"/LOG_WARNING


#####################################################################################################
#########################################     ФУНКЦИИ    ############################################
#####################################################################################################

# Функция убъет скрипт если он зависнет или будет слишком долго выполняться в зависимости от
# +установленного в функции времени. Расположена в самом начале тела скрипта.
kill_script () {
if ( \
find "$directory_destination"/* -maxdepth 0 -not -path "$directory_general" | egrep '[[:digit:]]{4}$' \
 && ls --time=birth "$directory_destination" | egrep '[[:digit:]]{4}$' \
 | head -n 1 | xargs -I {} ls "$directory_destination"/{}/LOG_WARNING &> /dev/null ); then
 echo -e "Предыдущий вариант скрипта был завершен аварийно с ошибкой \"164\". \
	\nУстановить какая команда привела к аварийному завершению скрипта можно в файле \
	\n$( ls --time=birth "$directory_destination" | head -n 1 \
	| xargs -I {} ls "$directory_destination"/{}/LOG_WARNING ) по инструкции к ошибке. \
	\nУстраните причину ошибки, удалите руками данный файл и перезапустите скрипт."
	exit 164
fi
sleep "$ACCEPTABLE_TIME" && ps -p "$$" &> /dev/null && \
 pstree -p "$$" | tee "$LOG_WARNING" | egrep -o '[0-9]{1,9}' | \
 sort -unr | xargs -t kill -15 &>> "$LOG_WARNING" &
}

# Функция сохранения реальных файлов, на которые ссылаются симольные ссылки
# +в копируемых директориях и файлах,
# +реальные файлы складываются в каталоги согласно своему местоположению, в каталог
# +"$directory_backup_dereference"
# Используется в функции "backup_directory_and_files()"
backup_link () {
if [ -n "$( find "$dirfile" -path $directory_destination -prune -false -o -type l -print 2> /dev/null )" ]
then
 if [ ! -d "$directory_backup_dereference" ]; then
  mkdir "$directory_backup_dereference"
 fi
 if [ -d "$dirfile" ]; then
 echo -e "`date +"%X"` Cохранение реальных файлов из символьных ссылок каталога: \
		      \n\t \"$dirfile\"" >> "$LOG"
	elif [ -f "$dirfile" ]; then
	 echo -e "`date +"%X"` Cохранение реального файла из символьной ссылки: \
				\n\t \"$dirfile\"" >> "$LOG"
 fi
 find "$dirfile" -path "$directory_destination" -prune -false -o -type l -exec \
 realpath {} \; | xargs -I {} rsync --bwlimit="$RSYNC_SPEED" -rlptgoR {} \
 "$directory_backup_dereference" 2> "$LOG_TMP" | log_function
fi
}


# Функция для читаемого форматирования вывода команд в файл "$LOG".
 log_function () {
 awk -v WIDTH=80 '{
		    while ( length>WIDTH ) {
			print "\t\t " substr($0,1,WIDTH);
			$0=substr($0, WIDTH+1);
			}
		     print "\t\t " $0;
		   }' >> "$LOG"
 cat "$LOG_TMP" | awk -v WIDTH=82 '{
		        if ( length<=WIDTH )
			 print "\t ERROR: " $0;
				else if ( length>WIDTH ) {
				 print "\t ERROR: " substr ($0,1,WIDTH);
				  while ( length>WIDTH ) {
				  $0=substr($0,WIDTH+1)
				  print "\t\t" substr ($0,1,WIDTH);
				 	}
				 }
}' >> "$LOG"
echo -e "\n" >> "$LOG"
}

#####################################################################################################
############################################   ТЕЛО   ###############################################
#####################################################################################################

# Создание, или проверка на наличие и доступность редактирования,
# +директории назначения для бэкапов "$directory_destination"
if [ ! -d "$directory_destination" ] && \
[ ! -w "${directory_destination%/*}" -o ! -x "${directory_destination%/*}" ]; then
 echo -e "Нет прав доступа для создания директории для бэкапов в указанном каталоге ${directory_destination%/*}. \
      \nОШИБКА 165. Запустите скрипт от рута, поменяйте права или укажите другую директорию!"
 exit 165
	elif [ ! -d "$directory_destination" ] && \
	[ -w "${directory_destination%/*}" -a -x "${directory_destination%/*}" ]; then
	mkdir -p "$directory_destination"
	mkdir -p "$directory_archive"
		elif [ -d "$directory_destination" ] && \
		[ ! -w "$directory_destination" -o ! -x "$directory_destination" ]; then
		echo -e "Директория для бэкапов $directory_destination существует, но нет прав для её редактирования. \
		\nОШИБКА 165. Запустите скрипт от рута, поменяйте права или укажите другую директорию!"
		exit 165
fi

# Функция убъет скрипт если он зависнет или будет слишком долго выполняться в зависимости от
# +установленного в функции времени.
kill_script

# Создание директорий для конкретного дневного бэкапа.
if [ ! -d "$directory_general" ] || [ ! -d "$directory_backup" ]; then
 mkdir -p "$directory_general" "$directory_backup"
fi

# Начало записей в логе
echo "Лог работы скрипта backup_.sh СТАРТ $(date +"%X %d.%m.%Y")" >> "$LOG"
echo -e "\n" >> "$LOG"

# Cоздаст папку для архива если её нет.
# +Если тарболов скопилось больше чем указано в переменной "$TAR_COUNT", удалит половину из них
# +а самый старый перенесёт в папку "$directory_archive".
if [ ! -d "$directory_archive" ]; then
 mkdir -p "$directory_archive"
fi
if [ $( find $directory_destination/* -maxdepth 0 -name '*.tar.bz2' | wc -l ) -ge "$TAR_COUNT" ]; then
 echo -e "`date +"%X"` Перемещение тарбола \
 $( ls --time=birth "$directory_destination"/*.tar.bz2 | tail -n 1 ) \
 \n         в папку $directory_archive. И удаление старых тарболлов." >> "$LOG"
 rsync --bwlimit="$RSYNC_SPEED" -lptgo \
		 $( ls --time=birth $directory_destination/*.tar.bz2 | tail -n 1 ) \
                 "$directory_archive" 2> "$LOG_TMP" && \
 ls --time=birth "$directory_destination"/*.tar.bz2 | tail -n $(($TAR_COUNT/2)) \
		 | xargs -t -I {} rm -rf {} | log_function
fi

# Архивирует предыдущий бэкап в тарбол и удаляет сам неархивированный бэкап.
find "$directory_destination"/* -maxdepth 0 -not -path "$directory_general" | egrep '[[:digit:]]{4}$' && \
 find "$directory_destination"/* -maxdepth 0 -not -path "$directory_general" -exec basename {} \; \
 | egrep '[[:digit:]]{4}$' \
 | xargs -t -I {} tar -cjf "$directory_destination"/{}.tar.bz2 -C "$directory_destination" {} && \
find "$directory_destination"/* -maxdepth 0 -not -path "$directory_general" | egrep '[[:digit:]]{4}$' \
 | xargs -t -I {} rm -rf {}


# Резервирование папок и файлов
# +указанных пользователем в переменной "$directorys_and_files"
# Копирование каталогов и файлов происходит в директорию назначения "$directory_destination".
for dirfile in $directorys_and_files; do
         # Eсли закомментить или удалить функцию backup_link(), то никакой отдельной обработки
         # +символьных ссылок производиться не будет, но они также будут просто копироваться в
         # +каталог назначения как обычные ссылки.
         backup_link
        if [ -d "$dirfile" ]; then
         echo -e "`date +"%X"` Рекурсивное копирование каталога: \
         \n         \"$dirfile\"" >> "$LOG"
         rsync --bwlimit="$RSYNC_SPEED" -rlptgoR --exclude=$directory_destination "$dirfile" \
         "$directory_backup" 2> "$LOG_TMP" | \
         log_function
                elif [ -f "$dirfile" ]; then
                 echo -e "`date +"%X"` Копирование файла: \
                 \n         \"$dirfile\"" >> "$LOG"
                 rsync --bwlimit="$RSYNC_SPEED" -lptgoR --exclude=$directory_destination "$dirfile" \
                 "$directory_backup" 2> "$LOG_TMP" | \
                 log_function
                        elif [ ! -d "$dirfile" -a ! -f "$dirfile" ]; then
                         echo -e "`date +"%X"` Указанный вами файл или каталог, не найдены: \
                         \n         \"$dirfile\" не существует!!!" >> "$LOG"
                         echo -e "\n" >> "$LOG"
        fi
done


# Удаление временного файла "$LOG_TMP" и завершение записей в логе.
rm -f "$LOG_TMP"
echo "Завершение работы скрипта backup_.sh КОНЕЦ $(date +"%X %d.%m.%Y")" >> "$LOG"
echo >> "$LOG"
echo -e "--------------------------------------------------------------------------------------\n" >> "$LOG"



exit 0


