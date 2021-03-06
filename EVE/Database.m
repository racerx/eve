//
//  Database.m
//  EVE
//
//  Created by Tobias Sommer on 8/23/12.
//  Copyright (c) 2012 Sommer. All rights reserved.
//

#import "Database.h"
#import "ApplicationSettings.h"
#import "NSFileManager+DirectoryLocations.h"
#import "FmdbMigrationManager.h"
#import "FMDB/FMDatabase.h"
#import "FMDB/FMDatabaseQueue.h"
#import "DDLog.h"
#import "Create_Dislayed_shortcuts_12_08_23.h"
#import "Create_GUI_ELEMENTS_12_08_23.h"
#import "Create_Disabled_Applications_12_08_23.h"
#import "Create_GUI_Supported_Application_12_08_23.h"
#import "Create_Learned_Shortcuts_12_08_23.h"
#import "Create_Menu_Bar_Shortcuts_12_08_23.h"
#import "Create_Indexing_Log_12_08_23.h"

static const int ddLogLevel = LOG_LEVEL_ERROR;

@implementation Database

+ (FMDatabaseQueue*) initDatabaseFromSupportDirectory {
  NSString *dbPath = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"database.db"]];
  FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
  FMDatabaseQueue *queue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
  
  
  if (![db open]) {
    DDLogError(@"Could not open db.");
    [NSApp terminate:self];
  }
  db.logsErrors = YES;
  
  [queue inDatabase:^(FMDatabase *db) {
  [db open];
  // Enable Foreign key support
  // enable foreign_key
  NSString *sql = @"PRAGMA foreign_keys = ON;";
  [db executeUpdate:sql];

    // Clean the Databases
      [db executeUpdate:@"DELETE FROM indexing_log"];
      [db executeUpdate:@"DELETE FROM sqlite_sequence WHERE name = 'indexing_log';"];
    
  [db close];
  }];

  return queue;
}

+ (void) executeMigrations :(NSString*) dbPath {
  NSArray *migrations = [NSArray arrayWithObjects:
                         [Create_Dislayed_shortcuts_12_08_23 migration], // 1
                         [Create_GUI_ELEMENTS_12_08_23 migration],
                         [Create_Disabled_Applications_12_08_23 migration],
                         [Create_GUI_Supported_Application_12_08_23 migration],
                         [Create_Learned_Shortcuts_12_08_23 migration],
                         [Create_Menu_Bar_Shortcuts_12_08_23 migration],
                         [Create_Indexing_Log_12_08_23 migration],
                         nil];
  [FmdbMigrationManager executeForDatabasePath:dbPath withMigrations:migrations];
}

@end
