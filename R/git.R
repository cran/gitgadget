#' Check error status
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param code Code returned by an API request
#'
#' @export
checkerr <- function(code) floor(code / 100) == 2
is_not <- function(x) length(x) == 0 || (length(x) == 1 && is.na(x))
is_empty <- function(x, empty = "\\s*") {
  is_not(x) || (length(x) == 1 && grepl(paste0("^", empty, "$"), x))
}
pressed <- function(x) !is.null(x) && (is.list(x) || x > 0)
not_pressed <- function(x) !pressed(x)

connect <- function(token = Sys.getenv("git.token"), server = "https://gitlab.com/api/v4/") {
  if (is_empty(token)) {
    stop("Token not available")
  } else {
    list(status = "OKAY", token = token)
  }
}
#' Reach user file
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param userfile File with student information
#' @param cols Column names that must exists in the file
#'
#' @export
read_ufile <- function(userfile, cols = c("userid", "team", "token")) {
  if (!file.exists(userfile)) {
    stop("Userfile does not exist")
  } else {
    users <- read.csv(userfile, stringsAsFactors = FALSE)
    if (all(cols %in% colnames(users))) {
      users
    } else {
      stop("Userfile must include the columns ", paste0(cols, collapse = ", "))
    }
  }
}

groupID <- function(name, path, token, server, page = 1) {
  h <- new_handle()
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, paste0("groups?per_page=100&page=", page, "&search=", name))
  resp <- curl_fetch_memory(murl, h)

  if (checkerr(resp$status_code) == FALSE) {
    return(list(status = "SERVER_ERROR"))
  }

  resp$content <- fromJSON(rawToChar(resp$content))

  ## check if group exists
  id <- which(name == resp$content$name & path == resp$content$path)
  if (length(id) == 0) {
    list(status = "NOSUCHGROUP")
  } else {
    list(status = "OKAY", group_id = resp$content$id[id])
  }
}

userIDs <- function(ids, token, server) {
  sapply(ids, function(id) {
    resp <- userID(id, token, server)
    ifelse(resp$status == "OKAY", resp$user_id[1], NA)
  })
}

userID <- function(id, token, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "GET")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  resp <- curl_fetch_memory(paste0(server, "users?username=", id), h)

  if (checkerr(resp$status_code) == FALSE) {
    return(list(status = "SERVER_ERROR", message = rawToChar(resp$content)))
  }

  uid <- fromJSON(rawToChar(resp$content))$id

  if (length(uid) == 0) {
    list(status = "NO_SUCH_USER")
  } else {
    list(status = "OKAY", user_id = uid[1])
  }
}

groupr <- function(groupname, path, token, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "groups?name=", groupname, "&path=", path, "&visibility_level=0")
  resp <- curl_fetch_memory(murl, h)
  if (checkerr(resp$status_code) == FALSE) {
    return(list(status = "SERVER_ERROR", message = rawToChar(resp$content)))
  }

  group_id <- fromJSON(rawToChar(resp$content))$id
  list(status = "OKAY", group_id = group_id)
}

#' Add users to a repo
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param repo Repo to update
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param permission Permission setting for the repo (default is 20, i.e., reporter)
#' @param server The GitLab API server
#'
#' @export
add_users_repo <- function(token, repo, userfile, permission = 20,
                           server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  resp <- projID(repo, token, server)

  if (resp$status != "OKAY") {
    message("Error finding repo: ", repo)
    return(invisible())
  }

  project_id <- resp$project_id
  user_data <- read_ufile(userfile, cols = c("userid", "token"))
  user_data$git_id <- userIDs(user_data$userid, token, server)

  setup <- function(dat) {
    add_user_repo(dat$git_id, project_id, token, permission, server = server)
    dat
  }

  resp <- user_data %>%
    group_by_at(.vars = "git_id") %>%
    do(setup(.))
}

add_user_repo <- function(user_id, repo_id, token, permission, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "projects/", repo_id, "/members?user_id=", user_id, "&access_level=", permission)
  resp <- curl_fetch_memory(murl, h)
  if (checkerr(resp$status_code) == FALSE) {
    mess <- fromJSON(rawToChar(resp$content))$message
    if (length(mess) > 0 && grepl("already exists", mess, ignore.case = TRUE)) {
      return(list(status = "OKAY", message = mess))
    } else {
      message("There was an error adding user", user_id, "to repo", repo_id, ":", mess, "\n")
      return(list(status = "SERVER_ERROR", message = mess))
    }
  }

  resp$content <- fromJSON(rawToChar(resp$content))
  list(status = "OKAY")
}

#' Remove users from a repo
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param repo Repo the update
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param server The GitLab API server
#'
#' @export
remove_users_repo <- function(token, repo, userfile, server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  resp <- projID(repo, token, server)

  if (resp$status != "OKAY") {
    message("Error finding repo: ", repo)
    return(invisible())
  }

  project_id <- resp$project_id
  user_data <- read_ufile(userfile, cols = c("userid", "token"))
  user_data$git_id <- userIDs(user_data$userid, token, server)

  setup <- function(dat) {
    remove_user_repo(dat$git_id, project_id, token, server = server)
    dat
  }

  resp <- user_data %>%
    group_by_at(.vars = "git_id") %>%
    do(setup(.))
}

remove_user_repo <- function(user_id, repo_id, token, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "DELETE")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "projects/", repo_id, "/members/", user_id)
  resp <- curl_fetch_memory(murl, h)
  if (checkerr(resp$status_code) == FALSE) {
    message("User ", user_id, " was not a member of repo ", repo_id, "\n")
    list(status = "SERVER_ERROR")
  } else {
    list(status = "OKAY")
  }
}

#' Create a group on GitLab using the API
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param groupname Group to create on GitLab (defaults to user's namespace)
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param permission Permission setting for the group (default is 20, i.e., reporter)
#' @param server The GitLab API server
#'
#' @export
create_group <- function(token, groupname = "", userfile = "",
                         permission = 20, server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  token <- resp$token
  resp <- groupID(groupname, groupname, token, server)

  if (resp$status == "NOSUCHGROUP") {
    resp <- groupr(groupname, groupname, token, server = server)
  }

  if (resp$status != "OKAY") {
    message("Unable to create or get group: ", resp$message)
    return(invisible())
  }

  # https://docs.gitlab.com/ee/api/access_requests.html
  permissions <- c(10, 20, 30, 40, 50)

  ## provide group permissions
  if (!is_empty(userfile) && permission %in% permissions) {
    course_id <- resp$group_id
    udat <- read_ufile(userfile)
    uids <- userIDs(udat$userid, token, server)
    add_users_group(uids, course_id, token, permission, server)
  }
}

get_allprojects <- function(token, server, namespace = "", owned = TRUE, search = "",
                            everything = FALSE, turn = 1, page = 1) {
  h <- new_handle()
  handle_setopt(h, customrequest = "GET")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)

  if (!is_empty(search)) {
    search <- paste0("&search=", search)
  }

  if (owned) {
    murl <- paste0(server, "projects?owned=true", search, "&per_page=100&page=", page)
  } else {
    murl <- paste0(server, "projects?membership=true", search, "&per_page=100&page=", page)
  }

  resp <- curl_fetch_memory(murl, h)

  if (checkerr(resp$status_code) == FALSE) {
    if (turn < 6) {
      message("SERVER_ERROR: Problem getting projects")
      message("Sleeping for 5 seconds and then trying again")
      Sys.sleep(5)
      return(get_allprojects(token, server, namespace = namespace, owned = owned, everything = everything, turn = turn + 1, page = page))
    } else {
      message("****************************************************************************")
      message("Tried 5 times and failed to get list of projects. GitLab message shown below")
      message("****************************************************************************")
      message(rawToChar(resp$content))
    }

    return(list(status = "SERVER_ERROR", message = rawToChar(resp$content)))
  }

  mainproj <- fromJSON(rawToChar(resp$content))

  nr_pages <- strsplit(rawToChar(resp$headers), "\n")[[1]] %>%
    .[grepl("X-Total-Pages", .)] %>%
    sub("X-Total-Pages:\\s+", "", .) %>%
    as.numeric()

  if (everything == FALSE && length(mainproj) > 0) {
    if (is.null(mainproj$forked_from_project)) {
      mainproj <- select_at(mainproj, c("id", "name", "path_with_namespace"))
    } else {
      mainproj <- select_at(mainproj, c("id", "name", "path_with_namespace", "forked_from_project"))
    }
  }

  if (!is_empty(nr_pages) > 0 && is.numeric(nr_pages) && nr_pages > page) {
    next_page <- get_allprojects(
      token, server,
      namespace = namespace, owned = owned, search = search,
      everything = everything, turn = turn, page = page + 1
    )
    np_mainproj <- next_page[["repos"]]
    if (is.data.frame(np_mainproj) && nrow(np_mainproj) > 0) {
      mainproj <- jsonlite::rbind_pages(list(mainproj, np_mainproj))
    }
  }
  list(status = "OKAY", repos = mainproj)
}

#' Find project ID
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param path_with_namespace Repo name together with the group or user namespace
#' @param token GitLab token
#' @param server The GitLab API server
#' @param owned Restrict listing to only repos owned by the user? TRUE or FALSE
#' @param search Search term to use to narrow down the set of projects
#'
#' @export
projID <- function(path_with_namespace, token, server, owned = TRUE, search = "") {
  resp <- get_allprojects(token, server, search = search, owned = owned)

  if (resp$status != "OKAY") {
    return(resp)
  }
  mainproj <- resp$repos
  if (is_empty(mainproj)) {
    message("No such repo: ", path_with_namespace)
    list(status = "NO_SUCH_REPO", message = "No such repo")
  } else {
    mainproj <- mainproj[mainproj$path_with_namespace == path_with_namespace, ]
    if (length(mainproj$id) == 0) {
      message("No such repo: ", path_with_namespace, "  Status code: ", mainproj$message)
      list(status = "NO_SUCH_REPO", message = "No such repo")
    } else {
      list(status = "OKAY", project_id = mainproj$id[1])
    }
  }
}

forkRepo <- function(token, project_id, server, turn = 1) {
  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "projects/", project_id, "/fork/")
  resp <- curl_fetch_memory(murl, h)
  if (checkerr(resp$status_code) == FALSE) {
    if (turn < 6) {
      message("SERVER_ERROR: Problem forking project")
      message("Sleeping for 5 seconds and then trying again")
      Sys.sleep(5)
      return(forkRepo(token, project_id, server, turn = turn + 1))
    } else {
      message("****************************************************************************")
      message("Tried 5 times and failed to fork project. GitLab message shown below")
      message("****************************************************************************")
      message(rawToChar(resp$content))
      list(status = "SERVER_ERROR", message = rawToChar(resp$content))
    }
  } else {
    content <- fromJSON(rawToChar(resp$content))
    list(status = "OKAY", content = content)
  }
}

## not currently used
renameRepo <- function(project_id, token, newname, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "PUT")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "projects/", project_id, "?name=", newname)
  resp <- curl_fetch_memory(murl, h)
  if (checkerr(resp$status_code) == FALSE) {
    message("Problem changing repo name")
    list(status = "SERVER_ERROR", message = rawToChar(resp$content))
  } else {
    list(status = "OKAY", name = fromJSON(rawToChar(resp$content))$name)
  }
}

setupteam <- function(token, leader, others, git_leader, git_others,
                      project_id, server, search = "") {
  ## fork if needed for team lead
  ## reset "everything" to FALSE to limit amount of information to pull (1/14/2023)
  resp <- get_allprojects(token, server, everything = FALSE, owned = TRUE, search = search)

  if (!"forked_from_project" %in% names(resp$repos) &&
    is_empty(resp$repos$forked_from_project) &&
    !project_id %in% resp$repos$forked_from_project$id &&
    !search %in% resp$repos$name ## added on 1/14/2023
  ) {
    message("Creating fork for ", leader)
    resp <- forkRepo(token, project_id, server)
    if (resp$status != "OKAY") {
      message("\nError forking for ", leader)
      return(invisible())
    }

    leader_project_id <- resp$content$id
    leader_project_name <- resp$content$name
    upstream_name <- resp$content$name
  } else {
    id <- length(which(resp$repos$forked_from_project$id == project_id))
    if (id == 0 && !is_empty(search)) {
      # for some reason the API is not returning "forked_from_project"
      # but (1) the project is still there but (2) the id is different
      # seems likely this will cause problems when fetching submissions
      # 1/14/2023
      if (length(which((resp$repos$name == search)) > 0)) {
        message("Project not in 'forked_from' but ", search, " still exists for ", leader, " ", resp$repos$id)
        id <- id + 1
      }
    }
    if (id > 0) {
      message("Assignment was already forked for ", leader)
    } else {
      message("Can't find repo ID for ", leader)
      return()
    }

    leader_project_id <- resp$repos$id[id]
    leader_project_name <- resp$repos$name[id]
    upstream_name <- resp$repos$forked_from_project$name[id]
  }

  ## add others as users
  if (length(others) > 0) {
    message("Adding ", paste0(others, collapse = ", "), " to ", leader, "'s repo")
    resp <- add_team(leader_project_id, token, data.frame(others, git_others), server)
  }
  invisible()
}

add_team <- function(proj_id, token, team_mates, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)

  apply(team_mates, 1, function(others) {
    murl <- paste0(
      server, "projects/", proj_id, "/members?user_id=",
      gsub(" ", "", others[2]), "&access_level=40"
    )
    resp <- curl_fetch_memory(murl, h)
    mess <- rawToChar(resp$content)
    if (checkerr(resp$status_code) == TRUE) {
      content <- fromJSON(rawToChar(resp$content))
      list(status = "OKAY", content = content)
    } else if (length(mess) > 0 && grepl("already exists", mess, ignore.case = TRUE)) {
      message(paste0("User ", others[1], " is already a member"))
      list(status = "OKAY", message = mess)
    } else {
      message("Error adding user ", others[1], " to team: server code ", resp$status_code)
      list(status = "SERVER_ERROR", content = rawToChar(resp$content))
    }
  })
}

#' Assign work to each student/team by creating a fork of the main repo
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param groupname Group to create on GitLab (defaults to user's namespace)
#' @param assignment Name of the assignment to assign
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param tafile A optional csv file with TA information (i.e., username, token, and email)
#' @param type Individual or Team work
#' @param pre Pre-amble for the assignment name, usually groupname + "-"
#' @param server The GitLab API server
#'
#' @export
assign_work <- function(token, groupname, assignment, userfile,
                        tafile = "", type = "individual", pre = "",
                        server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  if (is_empty(groupname)) {
    stop("A groupname is required to assign work. Please add a groupname and try again")
  }

  token <- resp$token
  upstream_name <- paste0(groupname, "/", paste0(pre, assignment))
  resp <- projID(upstream_name, token, server)

  if (resp$status != "OKAY") {
    stop("Error getting assignment ", upstream_name)
  }

  project_id <- resp$project_id

  add_users_df <- function(dat, permission) {
    add_user_repo(dat$git_id, project_id, token, permission, server = server)
    dat
  }
  remove_users_df <- function(dat) {
    remove_user_repo(dat$git_id, project_id, token, server = server)
    dat
  }

  student_data <- read_ufile(userfile)
  student_data$git_id <- userIDs(student_data$userid, token, server)

  if (type == "individual") {
    student_data$team <- paste0("team", seq_len(nrow(student_data)))
  }

  if (!is_empty(tafile)) {
    ta_data <- read_ufile(tafile, cols = c("userid", "token"))
    ta_data$git_id <- userIDs(ta_data$userid, token, server)
    ta_data$team <- "team0"

    resp <- ta_data %>%
      group_by_at(.vars = "git_id") %>%
      do(add_users_df(., 40))
  } else {
    ta_data <- head(student_data, 0)
  }

  leader <- 1
  teams <- unique(student_data$team)
  vars <- c("token", "userid", "git_id")
  setup <- function(dat) {
    ## adding access to the main repo
    resp <- dat %>%
      group_by_at(.vars = "git_id") %>%
      do(add_users_df(., 20))

    setup_dat <- bind_rows(dat[, vars], ta_data[, vars])
    setupteam(
      setup_dat$token[leader],
      setup_dat$userid[leader],
      setup_dat$userid[-leader],
      setup_dat$git_id[leader],
      setup_dat$git_id[-leader],
      project_id,
      server,
      search = assignment
    )

    ## removing access to the main repo
    resp <- dat %>%
      group_by_at(.vars = "git_id") %>%
      do(remove_users_df(.))
  }

  for (i in teams) {
    filter(student_data, team == i) %>%
      setup()
  }
}

maker <- function(repo_name, token, server, namespace = "") {
  if (namespace == "") {
    namespace_id <- namespace
  } else {
    resp <- groupID(namespace, namespace, token, server)

    if (resp$status == "NOSUCHGROUP") {
      message("Creating group ", namespace)
      resp <- groupr(namespace, namespace, token, server = server)
      resp <- groupID(namespace, namespace, token, server)
    } else if (resp$status != "OKAY") {
      print(resp)
      stop("Problem getting or creating group using the 'maker' function")
    }

    if (resp$status != "OKAY") {
      return(list(
        status = "NOSUCHGROUP",
        content = "Namespace to create repo does not exist"
      ))
    }
    namespace_id <- resp$group_id
  }

  ## check if repo already exists
  h <- new_handle()
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  murl <- paste0(server, "projects?owned=true", paste0("&search=", repo_name), "&per_page=100&page=1")
  if (!is_empty(namespace_id)) {
    murl <- paste0(murl, "&namespace_id=", namespace_id)
  }
  resp <- curl_fetch_memory(murl, h)
  content <- fromJSON(rawToChar(resp$content))
  id <- which(repo_name == content$name)

  if (length(id) > 0) {
    message("Got id for existing repo ", repo_name)
    return(list(status = "OKAY", repo_id = content$id[id[1]]))
  }

  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)

  murl <- paste0(server, "projects?", "name=", repo_name)
  if (!is_empty(namespace_id)) {
    murl <- paste0(murl, "&namespace_id=", namespace_id)
  }
  resp <- curl_fetch_memory(murl, h)
  content <- fromJSON(rawToChar(resp$content))
  if (checkerr(resp$status_code) == TRUE) {
    message("Created repo ", repo_name)
    list(status = "OKAY", repo_id = content$id)
  } else if (content$message$name == "has already been taken") {
    list(status = "OKAY", repo_id = content$id)
  } else {
    message("Error creating repo")
    list(status = "SERVER_ERROR", content = content)
  }
}

#' Create the main repo from a local directory
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param username Username
#' @param token Token (e.g., Sys.getenv("git.token") or Sys.getenv("GITHUB_PAT"))
#' @param repo Name of the repo (assignment)
#' @param base_dir Base directory for the repo. file.path(directory, assignment) should exist
#' @param groupname Group to create on GitLab (defaults to user's namespace)
#' @param pre Pre-amble for the repo (assignment) name
#' @param ssh Use SSH for authentication
#' @param server The GitLab API server
#'
#' @export
create_repo <- function(username = Sys.getenv("git.user"), token = Sys.getenv("git.token"),
                        repo = basename(getwd()), base_dir = dirname(getwd()), groupname = "",
                        pre = "", ssh = FALSE, server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check username/token/server")
  }

  token <- resp$token
  gn <- ifelse(groupname == "" || groupname == username, "", groupname)

  message("Making repo ", paste0(pre, repo), " in group ", ifelse(gn == "", username, gn))

  resp <- maker(paste0(pre, repo), token, server, gn)

  if (resp$status == "NOSUCHGROUP") {
    stop("Add group ", gn, " before pushing ", repo)
  }

  ## set directory and reset to current on function exit
  adir <- file.path(base_dir, repo)
  if (!dir.exists(adir)) {
    dir.create(adir, recursive = TRUE)
    cat("New repo created by gitgadget", file = file.path(adir, "README.md"))
  }

  owd <- setwd(adir)
  on.exit(setwd(owd))

  ## storing all git output in a temp file
  mess_file <- tempfile()

  ## initialize git repo if it doesn't exist yet
  if (!dir.exists(".git")) {
    system2("git", c("init", "-b", "main", ">>", mess_file, "2>&1"))
  }

  ## make sure .gitignore is added before create
  if (!file.exists(".gitignore")) {
    cat(".Rproj.user\n.Rhistory\n.RData\n.Ruserdata\n.DS_Store\n.ipynb_checkpoints\n.mypy_cache\n.vscode\n", file = ".gitignore")
  }

  ## avoid CI unless already setup by user
  if (!file.exists(".gitlab-ci.yml")) {
    cat("test:\n  script:\n  - echo \"\"", file = ".gitlab-ci.yml")
  }

  ## make project file if needed
  rproj <- list.files(path = adir, pattern = "*.Rproj")
  if (length(rproj) == 0) {
    cnt <- "Version: 1.0\n\nRestoreWorkspace: No\nSaveWorkspace: No\nAlwaysSaveHistory: Default\n\nEnableCodeIndexing: Yes\nUseSpacesForTab: Yes\nNumSpacesForTab: 2\nEncoding: UTF-8\n\nRnwWeave: knitr\nLaTex: pdfLaTeX\n\nAutoAppendNewline: Yes\n\nBuildType: Package\nPackageUseDevtools: Yes\nPackageInstallArgs: --no-multiarch --with-keep.source\nPackageRoxygenize: rd,collate,namespace\n"
    cat(cnt, file = paste0(basename(adir), ".Rproj"))
  }

  vscode <- list.files(path = adir, pattern = "*.code-workspace")
  if (length(vscode) == 0) {
    cnt <- '{"folders": [{"path": "."}], "settings": {}}'
    cat(cnt, file = paste0(basename(adir), ".code-workspace"))
  }

  url <- sub("\\s*(https://|http://)?([^/:]+).*", "\\1\\2", server)

  if (gn == "") gn <- username
  if (isTRUE(ssh)) {
    url <- sub("(https://|http://)", "git@", url)
    murl <- paste0(url, ":", gn, "/", paste0(pre, repo), ".git")
  } else {
    murl <- paste0(url, "/", gn, "/", paste0(pre, repo), ".git")
  }
  murl <- gsub("//", "/", murl)
  rorg <- system("git remote -v", intern = TRUE)

  if (length(rorg) == 0) {
    system2("git", c("remote", "add", "origin", murl, ">>", mess_file, "2>&1"))
  } else {
    system2("git", c("remote", "set-url", "origin", murl, ">>", mess_file, "2>&1"))
  }

  ## allow fetching of MRs
  ## https://gitlab.com/gitlab-org/gitlab-ce/blob/master/doc/workflow/merge_requests.md#checkout-merge-requests-locally
  remote_fetch <- system("git config --get-all remote.origin.fetch", intern = TRUE)
  if (!"+refs/merge-requests/*/head:refs/remotes/origin/merge-requests/*" %in% remote_fetch) {
    system("git config --add remote.origin.fetch +refs/merge-requests/*/head:refs/remotes/origin/merge-requests/*")
  }

  current_branch <- system("git branch --show-current", intern = TRUE)

  system2("git", c("add", ".", ">>", mess_file, "2>&1"))
  system2("git", c("commit", "-m", '"Upload repo using gitgadget"', ">>", mess_file, "2>&1"))
  system2("git", c("push", "-u", "origin", current_branch, ">>", mess_file, "2>&1"))

  # return messages
  paste0(readLines(mess_file), collapse = "\n")
}

merger <- function(token, to, search = "", server,
                   title = "submission",
                   frombranch = "main",
                   tobranch = "main") {
  resp <- get_allprojects(token[1], server, search = search)

  if (length(resp$repos) == 0) {
    return()
  } else {
    forked <- resp$repos[resp$repos$forked_from_project$id == to, ]
  }

  if (length(forked) == 0) {
    message("Error trying to find fork")
    message(resp)
    return(list(status = "ERROR", content = resp))
  }

  from <- na.omit(forked$id)[1]

  if (length(from) == 0) {
    message("No fork found")
    return(list(status = "ERROR", content = ""))
  }

  h <- new_handle()
  handle_setopt(h, customrequest = "POST")
  handle_setheaders(h, "PRIVATE-TOKEN" = token[1])
  murl <- paste0(
    server, "projects/", from, "/merge_requests?source_branch=",
    frombranch, "&target_branch=", tobranch, "&title=", title,
    "&target_project_id=", to
  )

  resp <- curl_fetch_memory(murl, h)
  resp$content <- fromJSON(rawToChar(resp$content))
  if (checkerr(resp$status_code) == TRUE) {
    message("Generating merge request for ", token[2])
    list(status = "OKAY", content = resp$content)
  } else if (grepl("This merge request already exists", resp$content)) {
    message("Merge request already exists for ", token[2])
    list(status = "OKAY", content = resp$content)
  } else {
    message("Error creating merge request for ", token[2], " Code: ", resp$status_code)
    message(resp$content)
    list(status = "ERROR", content = resp$content)
  }
}

check_status <- function(token, assignment, userfile,
                         type = "individual",
                         server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  token <- resp$token
  search <- strsplit(assignment, "/")[[1]] %>%
    (function(x) ifelse(length(x) > 1, x[2], x[1]))
  resp <- projID(assignment, token, server, owned = TRUE, search = search)

  if (resp$status != "OKAY") {
    resp <- projID(assignment, token, server, owned = FALSE, search = search)
    if (resp$status != "OKAY") {
      stop("Error getting assignment ", assignment)
    }
  }

  project_id <- resp$project_id
  udat <- read_ufile(userfile)

  if (type == "individual") {
    udat$team <- paste("ind", seq_len(nrow(udat)))
  } else {
    ## MR only from team lead
    udat <- group_by_at(udat, .vars = "team") %>%
      slice(1)
  }

  ## getting the actual status
  get_status <- function(st_token, server = server, search = search) {
    resp <- get_allprojects(st_token, server, search = search)
    if (inherits(resp$repo, "data.frame") && nrow(resp$repos) > 1) {
      resp$repos <- filter(resp$repos, name == {{ search }})
    }
    pid <- resp$repos$id
    if (length(pid) != 1) {
      list("unclear", 0)
    } else {
      h <- new_handle()
      handle_setopt(h, customrequest = "GET")
      handle_setheaders(h, "PRIVATE-TOKEN" = st_token[1])
      murl <- paste0(server, "projects/", pid, "/pipelines")
      resp <- curl_fetch_memory(murl, h)
      resp$content <- fromJSON(rawToChar(resp$content))
      status <- resp$content$status
      if (length(status) == 0) status <- "unknown"
      list(status[1], length(status))
    }
  }

  udat$status <- "unknown"
  udat$attempts <- 0
  for (i in seq_len(nrow(udat))) {
    udat[i, c("status", "attempts")] <- get_status(as.character(udat[i, "token"]), server, search)
  }

  rbind(
    filter(udat, status == "unknown"),
    filter(udat, status == "failed"),
    filter(udat, !status %in% c("unknown", "failed"))
  )
}

#' Create merge requests for each student/team
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param assignment Name of the assignment (e.g., "class345/class345-assignment1")
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param type Individual or Team work
#' @param server The GitLab API server
#'
#' @export
collect_work <- function(token, assignment, userfile,
                         type = "individual",
                         server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  token <- resp$token
  search <- strsplit(assignment, "/")[[1]] %>%
    (function(x) ifelse(length(x) > 1, x[2], x[1]))
  resp <- projID(assignment, token, server, owned = TRUE, search = search)

  if (resp$status != "OKAY") {
    resp <- projID(assignment, token, server, owned = FALSE, search = search)
    if (resp$status != "OKAY") {
      stop("Error getting assignment ", assignment)
    }
  }

  project_id <- resp$project_id
  udat <- read_ufile(userfile)

  if (type == "individual") {
    udat$team <- paste("ind", seq_len(nrow(udat)))
  } else {
    ## MR only from team lead
    udat <- group_by_at(udat, .vars = "team") %>%
      slice(1)
  }

  udat$git_id <- userIDs(udat$userid, token, server)

  add_users_df <- function(dat, permission) {
    add_user_repo(dat$git_id, project_id, token, permission, server = server)
    dat
  }
  remove_users_df <- function(dat) {
    remove_user_repo(dat$git_id, project_id, token, server = server)
    dat
  }

  ## ensuring that users have the required access to create a merge request
  resp <- udat %>%
    group_by_at(.vars = "git_id") %>%
    do(add_users_df(., 20))

  resp <- apply(udat[, c("token", "userid")], 1, merger, project_id, search = search, server)

  ## removing user access
  resp <- udat %>%
    group_by_at(.vars = "git_id") %>%
    do(remove_users_df(.))

  message("Finished attempt to collect all merge requests. Check the console for messages\n")
}

#' Fetch all merge requests as local branches and link to a remote
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param assignment Name of the assignment (e.g., "class345/class345-assignment1")
#' @param page Number of the results page to select
#' @param server The GitLab API server
#'
#' @export
fetch_work <- function(token, assignment, page = 1,
                       server = "https://gitlab.com/api/v4/") {
  resp <- connect(token, server)
  if (resp$status != "OKAY") {
    stop("Error connecting to server: check token/server")
  }

  token <- resp$token

  search <- strsplit(assignment, "/")[[1]] %>%
    (function(x) ifelse(length(x) > 1, x[2], x[1]))
  resp <- projID(assignment, token, server, owned = TRUE, search = search)

  if (resp$status != "OKAY") {
    resp <- projID(assignment, token, server, owned = FALSE, search = search)
    if (resp$status != "OKAY") {
      stop("Error getting assignment ", assignment)
    }
  }

  project_id <- resp$project_id

  h <- new_handle()
  handle_setopt(h, customrequest = "GET")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)

  ## collecting information on (max) 100 merge requests
  resp <- curl_fetch_memory(
    paste0(
      server, "projects/", project_id,
      "/merge_requests?state=all&per_page=100&page=", page
    ),
    h
  )

  nr_pages <- strsplit(rawToChar(resp$headers), "\n")[[1]] %>%
    .[grepl("X-Total-Pages", .)] %>%
    sub("X-Total-Pages:\\s+", "", .) %>%
    as.numeric()

  next_page <- if (!is_empty(nr_pages) && is.numeric(nr_pages) && nr_pages > page) TRUE else FALSE
  mr <- fromJSON(rawToChar(resp$content))
  mrdat <-
    tibble(id = mr$iid, un = mr$author$username) %>%
    arrange(un, desc(id)) %>%
    group_by(un) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(id = as.character(id)) ## needed to ensure there are no spaces in branch name

  system("git fetch origin +refs/merge-requests/*/head:refs/remotes/origin/merge-requests/*")

  branches <- system("git branch ", intern = TRUE) %>% gsub("[\\* ]+", "", .)

  create_branch <- function(dat) {
    if (any(grepl(dat[["un"]], branches))) {
      system(paste0("git checkout ", dat[["un"]]))
      system(paste0("git merge origin/merge-requests/", dat[["id"]], " ", dat[["un"]]))
      ## the next two steps will commit, even if there is a merge conflict
      ## that way the process won't stop for a single branch/MR with a conflict
      system("git add .")
      system("git commit -m \"Update local branch with MR\"")
      system(paste0("git branch -d -r origin/merge-requests/", dat[["id"]]))
      system(paste0("git push"))
    } else {
      cat("Creating local and remote branch for ", dat[["un"]], "\n")
      system(paste0("git checkout -b ", dat[["un"]], " origin/merge-requests/", dat[["id"]]))
      system(paste0("git branch -d -r origin/merge-requests/", dat[["id"]]))
      system(paste0("git push --set-upstream origin ", dat["un"]))
    }
  }

  tmp <- apply(mrdat, 1, create_branch)

  if (next_page) {
    fetch_work(token, assignment, server = server, page = page + 1)
    message(paste0("Finished fetch attempt for page ", page, "\n"))
  } else {
    # useful if some branches are, for some reason, not available on the remote
    system("git push --all origin")
    message("Finished fetch attempt. Check the console for messages\n")
  }
}

remove_group <- function(token, groupname, server) {
  resp <- groupID(groupname, groupname, token, server)

  id <- resp$group_id
  h <- new_handle()
  handle_setopt(h, customrequest = "DELETE")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  resp <- curl_fetch_memory(paste0(server, "groups/", id), h)
}

remove_projects <- function(token, server) {
  ids <- get_allprojects(token, server, owned = TRUE)
  sapply(ids$repos$id, function(id) {
    remove_project(token, id, server)
  })
}

#' Remove a project
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param token GitLab token
#' @param id Project ID
#' @param server The GitLab API server
#'
#' @export
remove_project <- function(token, id, server) {
  h <- new_handle()
  handle_setopt(h, customrequest = "DELETE")
  handle_setheaders(h, "PRIVATE-TOKEN" = token)
  resp <- curl_fetch_memory(paste0(server, "projects/", id), h)
}

remove_student_projects <- function(userfile, server) {
  udat <- read_ufile(userfile)
  sapply(udat$token, remove_projects, server)
}

#' Check student tokens
#'
#' @details See \url{https://github.com/vnijs/gitgadget} for additional documentation
#'
#' @param userfile A csv file with student information (i.e., username, token, and email)
#' @param server The GitLab API server
#'
#' @export
check_tokens <- function(userfile, server = Sys.getenv("git.server", "https://gitlab.com/api/v4/")) {
  students <- read_ufile(userfile, cols = c("userid", "token", "email"))

  ## testing if student tokens work
  for (i in seq_len(nrow(students))) {
    token <- students[i, "token"]
    if (!is_empty(token)) {
      id <- get_allprojects(token, server, owned = TRUE)
    } else {
      id$status <- "EMPTY"
    }

    userid <- students[i, "userid"]
    email <- students[i, "email"]
    if (id$status == "OKAY") {
      id_check <- userID(userid, token, server)
      if (isTRUE(id_check$status == "OKAY")) {
        type <- "OKAY: "
      } else {
        type <- "NOT OKAY (ID): "
      }
    } else {
      type <- "NOT OKAY (TOKEN): "
    }
    cat(paste0(type, userid, " ", token, " <a href=\"mailto:", email, "\" target=\"_blank\">", email, "</a></br>"))
  }
}
